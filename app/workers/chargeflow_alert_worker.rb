# ChargeflowAlertWorker
#
# Handles Chargeflow `alerts.created` webhook events.
#
# When Chargeflow fires an alert for a transaction, this worker:
#   1. Locates the payment by the transaction/charge ID in the payload.
#   2. Applies a $100 alert fee to the plan (increments chargeflow_alert_fee).
#   3. Stores the Chargeflow alert ID on the payment record.
#   4. Adds the "chargeback" tag to both the law firm GHL contact and the
#      Fund Forge GHL contact for the user.
#   5. Fires the existing GHL chargeback event webhook (GhlChargebackWorker).
#
# Usage (called by ChargeflowController):
#   ChargeflowAlertWorker.perform_async(raw_json_string)
#
class ChargeflowAlertWorker
  include Sidekiq::Worker
  sidekiq_options queue: :default, retry: 3

  ALERT_FEE = 100.to_d
  CHARGEBACK_TAG = "chargeback".freeze

  def perform(raw_payload)
    payload = JSON.parse(raw_payload)
    Rails.logger.info("[ChargeflowAlert] Processing alert payload")

    # ── 1. Extract identifiers from the Chargeflow payload ──────────────────
    alert_id    = extract_alert_id(payload)
    charge_id   = extract_charge_id(payload)

    unless charge_id.present?
      Rails.logger.warn("[ChargeflowAlert] No charge/transaction ID found in payload — skipping")
      return
    end

    # ── 2. Find the matching payment ─────────────────────────────────────────
    payment = Payment.find_by(charge_id: charge_id)

    unless payment
      Rails.logger.warn("[ChargeflowAlert] No payment found for charge_id=#{charge_id} — skipping")
      return
    end

    plan = payment.plan
    user = payment.user

    Rails.logger.info("[ChargeflowAlert] Matched payment_id=#{payment.id} plan_id=#{plan.id} user_id=#{user.id}")

    # ── 3. Apply $100 alert fee to the plan ──────────────────────────────────
    plan.with_lock do
      new_fee = (plan.chargeflow_alert_fee.to_d + ALERT_FEE).round(2)
      plan.update_columns(chargeflow_alert_fee: new_fee, updated_at: Time.current)
      Rails.logger.info("[ChargeflowAlert] Applied $#{ALERT_FEE} fee to plan_id=#{plan.id} — total_alert_fee=#{new_fee}")
    end

    # ── 4. Store alert ID on payment ─────────────────────────────────────────
    if alert_id.present?
      payment.update_columns(chargeflow_alert_id: alert_id, updated_at: Time.current)
    end

    # ── 5. Add "chargeback" tag to GHL contacts ───────────────────────────────
    add_chargeback_tags(user)

    # ── 6. Fire GHL chargeback event webhook ─────────────────────────────────
    GhlChargebackWorker.perform_async(plan.id)

    Rails.logger.info("[ChargeflowAlert] Completed for payment_id=#{payment.id}")
  rescue JSON::ParserError => e
    Rails.logger.error("[ChargeflowAlert] JSON parse error: #{e.message}")
    raise
  rescue StandardError => e
    Rails.logger.error("[ChargeflowAlert] Error: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    raise
  end

  private

  # ── Payload parsing helpers ─────────────────────────────────────────────────

  def extract_alert_id(payload)
    payload.dig("id") ||
      payload.dig("data", "id") ||
      payload.dig("alert", "id") ||
      payload.dig("data", "alert", "id")
  end

  def extract_charge_id(payload)
    # Chargeflow may nest the transaction ID under various keys depending on the
    # payment processor. We check the most common paths.
    payload.dig("transaction_id") ||
      payload.dig("charge_id") ||
      payload.dig("data", "transaction_id") ||
      payload.dig("data", "charge_id") ||
      payload.dig("data", "payment", "transaction_id") ||
      payload.dig("data", "payment", "charge_id") ||
      payload.dig("alert", "transaction_id") ||
      payload.dig("alert", "charge_id") ||
      payload.dig("data", "alert", "transaction_id") ||
      payload.dig("data", "alert", "charge_id")
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
      Rails.logger.warn("[ChargeflowAlert] No law firm GHL contact found for user_id=#{user.id}")
    end

    # Fund Forge GHL contact
    ff_firm_user = FirmUser.joins(:firm)
                           .where(user: user, firms: { name: "Fund Forge" })
                           .where.not(ghl_fund_forge_id: [nil, ""])
                           .first

    if ff_firm_user&.ghl_fund_forge_id.present?
      ff_firm    = ff_firm_user.firm
      api_key    = ff_firm.ghl_api_key.presence || ENV["FUND_FORGE_API_KEY"]
      loc_id     = ff_firm.location_id.presence || ENV["FUND_FORGE_LOCATION_ID"]
      if api_key.present? && loc_id.present?
        result = GhlService.new(api_key, loc_id)
                           .add_tags(ff_firm_user.ghl_fund_forge_id, [CHARGEBACK_TAG])
        log_tag_result("fund_forge", "Fund Forge", ff_firm_user.ghl_fund_forge_id, result)
      end
    else
      Rails.logger.warn("[ChargeflowAlert] No Fund Forge GHL contact found for user_id=#{user.id}")
    end
  end

  def log_tag_result(context, firm_name, contact_id, result)
    if result[:success]
      Rails.logger.info("[ChargeflowAlert] Added 'chargeback' tag [#{context}] firm=#{firm_name} contact_id=#{contact_id}")
    else
      Rails.logger.error("[ChargeflowAlert] Failed to add 'chargeback' tag [#{context}] firm=#{firm_name} contact_id=#{contact_id} status=#{result[:status]} body=#{result[:body].inspect}")
    end
  end
end
