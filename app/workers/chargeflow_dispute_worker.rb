# ChargeflowDisputeWorker
#
# Handles Chargeflow `dispute.created` webhook events.
#
# Chargeflow automatically refunds the disputed transaction. This worker
# updates Fund Forge records and schedules a recovery charge:
#
#   1. Locates the payment by the transaction/charge ID in the payload.
#   2. Marks the original payment as disputed (disputed: true, status: :failed,
#      disputed_at: now) so remaining_balance_logic no longer counts it as paid,
#      effectively restoring the disputed amount to the outstanding balance.
#   3. Stores the Chargeflow dispute ID on the original payment record.
#   4. Applies a $100 dispute fee to the plan (chargeflow_alert_fee).
#   5. Creates a new recovery Payment for (disputed_amount + $100 fee) scheduled
#      for the next qualifying payday. This payment is a standard monthly_payment
#      and flows through the existing RecurringChargeService retry loop:
#        • Soft decline  → rescheduled on next payday within 28-day window
#        • Hard decline  → needs_new_card: true; SpreedlyAccountUpdaterWorker
#                          requeues it automatically when a new card arrives
#   6. Adds the "chargeback" tag to both the law firm GHL contact and the
#      Fund Forge GHL contact for the user.
#   7. Fires the existing GHL chargeback event webhook (GhlChargebackWorker).
#
# Usage (called by ChargeflowController):
#   ChargeflowDisputeWorker.perform_async(raw_json_string)
#
class ChargeflowDisputeWorker
  include Sidekiq::Worker
  sidekiq_options queue: :default, retry: 3

  DISPUTE_FEE    = 100.to_d
  CHARGEBACK_TAG = "chargeback".freeze

  # Payday schedule constants — mirrors RecurringChargeService
  BIWEEKLY_ANCHOR = Date.new(2024, 1, 5)  # Friday, Jan 5 2024
  MIN_GAP_DAYS    = 1

  def perform(raw_payload)
    payload = JSON.parse(raw_payload)
    Rails.logger.info("[ChargeflowDispute] Processing dispute payload")

    # ── 1. Extract identifiers ────────────────────────────────────────────────
    dispute_id = extract_dispute_id(payload)
    charge_id  = extract_charge_id(payload)

    unless charge_id.present?
      Rails.logger.warn("[ChargeflowDispute] No charge/transaction ID found in payload — skipping")
      return
    end

    # ── 2. Find the matching payment ──────────────────────────────────────────
    # Chargeflow's transactionId is the processor/gateway transaction ID,
    # stored as processor_transaction_id on our payments.
    payment = Payment.find_by(processor_transaction_id: charge_id)
    payment ||= Payment.find_by(charge_id: charge_id) # fallback for legacy records

    unless payment
      Rails.logger.warn("[ChargeflowDispute] No payment found for charge_id=#{charge_id} — skipping")
      return
    end

    plan = payment.plan
    user = payment.user

    Rails.logger.info("[ChargeflowDispute] Matched payment_id=#{payment.id} plan_id=#{plan.id} user_id=#{user.id}")

    # Determine the disputed amount before we change the payment record
    disputed_amount = payment.total_payment_including_fee.to_d

    recovery_payment = nil

    ActiveRecord::Base.transaction do
      # ── 3. Mark original payment as disputed ──────────────────────────────
      # Setting status: :failed means remaining_balance_logic no longer counts
      # this payment as "paid", restoring the disputed amount to the balance.
      payment.update!(
        disputed:              true,
        disputed_at:           Time.current,
        chargeflow_dispute_id: dispute_id.presence,
        status:                :failed,
        decline_reason:        "chargeflow_dispute",
        needs_new_card:        false
      )
      Rails.logger.info("[ChargeflowDispute] Marked payment_id=#{payment.id} as disputed — balance restored by #{disputed_amount}")

      # ── 4. Apply $100 dispute fee to the plan ────────────────────────────
      plan.with_lock do
        new_fee = (plan.chargeflow_alert_fee.to_d + DISPUTE_FEE).round(2)
        plan.update_columns(chargeflow_alert_fee: new_fee, updated_at: Time.current)
        Rails.logger.info("[ChargeflowDispute] Applied $#{DISPUTE_FEE} fee to plan_id=#{plan.id} — total_fee=#{new_fee}")
      end

      # ── 5. Create recovery payment ────────────────────────────────────────
      # Recovery amount = disputed amount + $100 fee
      recovery_amount = (disputed_amount + DISPUTE_FEE).round(2)
      scheduled_date  = next_payday_from(Date.current)

      # Resolve the payment method: use the same one as the disputed payment,
      # falling back to the user's default card.
      recovery_pm = payment.payment_method.presence ||
                    user.payment_methods.ordered_for_user.first

      unless recovery_pm
        Rails.logger.warn("[ChargeflowDispute] No payment method found for user_id=#{user.id} — cannot create recovery payment")
        raise ActiveRecord::Rollback
      end

      recovery_payment = Payment.create!(
        plan:                      plan,
        user:                      user,
        payment_method:            recovery_pm,
        payment_type:              :monthly_payment,
        payment_amount:            recovery_amount,
        total_payment_including_fee: recovery_amount,
        transaction_fee:           DISPUTE_FEE,
        status:                    :pending,
        scheduled_at:              scheduled_date.beginning_of_day,
        retry_count:               0,
        needs_new_card:            false,
        chargeflow_recovery:       true,
        decline_reason:            nil
      )

      Rails.logger.info(
        "[ChargeflowDispute] Created recovery payment_id=#{recovery_payment.id} " \
        "amount=#{recovery_amount} scheduled=#{scheduled_date} for plan_id=#{plan.id}"
      )
    end

    # ── 6. Immediately attempt the recovery charge ────────────────────────────
    # Enqueue ChargePaymentWorker right away — if it's a hard decline, the worker
    # sets needs_new_card: true and SpreedlyAccountUpdaterWorker requeues it when
    # a new card arrives. If it's a soft decline, RecurringChargeService reschedules
    # it on the next payday within the 28-day window.
    if recovery_payment
      ChargePaymentWorker.perform_async(recovery_payment.id)
      Rails.logger.info("[ChargeflowDispute] Enqueued ChargePaymentWorker for recovery payment_id=#{recovery_payment.id}")
    end

    # ── 7. Add "chargeback" tag to GHL contacts ───────────────────────────────
    add_chargeback_tags(user)

    # ── 8. Fire GHL chargeback event webhook ─────────────────────────────────
    GhlChargebackWorker.perform_async(plan.id)

    Rails.logger.info("[ChargeflowDispute] Completed for original payment_id=#{payment.id}")
  rescue JSON::ParserError => e
    Rails.logger.error("[ChargeflowDispute] JSON parse error: #{e.message}")
    raise
  rescue StandardError => e
    Rails.logger.error("[ChargeflowDispute] Error: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    raise
  end

  private

  # ── Payload parsing helpers ─────────────────────────────────────────────────

  def extract_dispute_id(payload)
    payload.dig("id") ||
      payload.dig("data", "id") ||
      payload.dig("dispute", "id") ||
      payload.dig("data", "dispute", "id")
  end

  def extract_charge_id(payload)
    payload.dig("transaction_id") ||
      payload.dig("charge_id") ||
      payload.dig("data", "transaction_id") ||
      payload.dig("data", "charge_id") ||
      payload.dig("data", "payment", "transaction_id") ||
      payload.dig("data", "payment", "charge_id") ||
      payload.dig("dispute", "transaction_id") ||
      payload.dig("dispute", "charge_id") ||
      payload.dig("data", "dispute", "transaction_id") ||
      payload.dig("data", "dispute", "charge_id")
  end

  # ── Payday scheduling ───────────────────────────────────────────────────────
  # Returns the next qualifying payday strictly after today (minimum 1 day gap).
  # Mirrors RecurringChargeService#next_payday_after logic.
  def next_payday_from(from_date)
    candidate = from_date + MIN_GAP_DAYS
    # Look up to 60 days out to find the next payday
    60.times do
      return candidate if payday?(candidate)
      candidate += 1
    end
    # Fallback: if no payday found within 60 days, schedule for tomorrow
    from_date + 1
  end

  def payday?(date)
    return true if date.day == 1
    return true if date.day == 15
    return true if biweekly_friday?(date)
    return true if date.wday == 4  # Thursday
    return true if date.wday == 5  # Friday
    false
  end

  def biweekly_friday?(date)
    return false unless date.wday == 5  # Must be a Friday
    days_since_anchor = (date - BIWEEKLY_ANCHOR).to_i
    (days_since_anchor % 14).zero?
  end

  # ── GHL tag helpers ─────────────────────────────────────────────────────────

  def add_chargeback_tags(user)
    # Law firm GHL contact
    law_firm_user = FirmUser.joins(:firm)
                            .where(user: user)
                            .where.not(firms: { name: "Fund Forge" })
                            .where.not(contact_id: [nil, ""])
                            .order(updated_at: :desc)
                            .first

    if law_firm_user&.contact_id.present?
      firm = law_firm_user.firm
      if firm.ghl_api_key.present? && firm.location_id.present?
        result = GhlService.new(firm.ghl_api_key, firm.location_id)
                           .add_tags(law_firm_user.contact_id, [CHARGEBACK_TAG])
        log_tag_result("law_firm", firm.name, law_firm_user.contact_id, result)
      end
    else
      Rails.logger.warn("[ChargeflowDispute] No law firm GHL contact found for user_id=#{user.id}")
    end

    # Fund Forge GHL contact
    ff_firm_user = FirmUser.joins(:firm)
                           .where(user: user, firms: { name: "Fund Forge" })
                           .where.not(ghl_fund_forge_id: [nil, ""])
                           .first

    if ff_firm_user&.ghl_fund_forge_id.present?
      ff_firm  = ff_firm_user.firm
      api_key  = ff_firm.ghl_api_key.presence || ENV["FUND_FORGE_API_KEY"]
      loc_id   = ff_firm.location_id.presence || ENV["FUND_FORGE_LOCATION_ID"]
      if api_key.present? && loc_id.present?
        result = GhlService.new(api_key, loc_id)
                           .add_tags(ff_firm_user.ghl_fund_forge_id, [CHARGEBACK_TAG])
        log_tag_result("fund_forge", "Fund Forge", ff_firm_user.ghl_fund_forge_id, result)
      end
    else
      Rails.logger.warn("[ChargeflowDispute] No Fund Forge GHL contact found for user_id=#{user.id}")
    end
  end

  def log_tag_result(context, firm_name, contact_id, result)
    if result[:success]
      Rails.logger.info("[ChargeflowDispute] Added 'chargeback' tag [#{context}] firm=#{firm_name} contact_id=#{contact_id}")
    else
      Rails.logger.error("[ChargeflowDispute] Failed to add 'chargeback' tag [#{context}] firm=#{firm_name} contact_id=#{contact_id} status=#{result[:status]} body=#{result[:body].inspect}")
    end
  end
end
