class GhlInboundWebhookWorker
  include Sidekiq::Worker

  def perform(payment_id, event_name = nil, _request_headers = nil)
    payment = Payment.find(payment_id)
    plan    = payment.plan
    user    = payment.user

    # Determine the event name
    resolved_event = event_name.presence || GhlInboundWebhookService.default_event_for_payment(payment)

    # Guard: only fire if the contact exists in our database (has email or phone)
    unless user.email.present? || user.phone.present?
      Rails.logger.warn("[GHL Payment Webhook Worker] Skipping — user has no email or phone, user_id=#{user.id}")
      return :no_contact_identity
    end

    webhook_url = GhlInboundWebhookService.resolve_webhook_url
    if webhook_url.blank?
      Rails.logger.warn("[GHL Payment Webhook Worker] Missing webhook URL, skipping payment_id=#{payment.id}")
      return :missing_webhook_url
    end

    GhlInboundWebhookService.new(webhook_url).call(
      payload_for(payment: payment, plan: plan, event_name: resolved_event),
      context: {
        worker: self.class.name,
        payment_id: payment.id,
        plan_id: plan.id,
        user_id: payment.user_id,
        event_name: resolved_event
      }
    )
  end

  private

  def payload_for(payment:, plan:, event_name:)
    user          = payment.user
    agreement     = plan.agreement
    total_payment = plan.total_payment.to_d
    total_interest = plan.total_interest_amount.to_d
    total_amount  = total_payment + total_interest
    next_payment_due = plan.next_payment_at || plan.calculated_next_payment_at
    status = event_name.presence || GhlInboundWebhookService.default_event_for_payment(payment)

    # overdue when: payment explicitly failed, needs new card, or the plan's next due date has passed
    is_overdue = status == GhlInboundWebhookService::PAYMENT_FAILED_EVENT ||
                 status == GhlInboundWebhookService::NEEDS_NEW_CARD_EVENT ||
                 (payment.respond_to?(:needs_new_card?) && payment.needs_new_card?) ||
                 plan_overdue?(plan)

    payment_amount = payment.total_payment_including_fee.presence || payment.payment_amount.to_d
    # If payment_amount == total_amount, client paid everything upfront — down_payment equals payment_amount
    down_payment = payment_amount.to_d == total_amount ? payment_amount.to_d : plan.down_payment.to_d

    # Installment amount: monthly payment for payment plans; equals payment_amount for PIF
    installment_amount = plan.monthly_payment.to_d.nonzero? || payment_amount.to_d

    # Remaining balance: never negative — floor at 0
    remaining_balance = [plan.remaining_balance_logic.to_d, 0].max

    # Retry metadata
    retry_count    = payment.respond_to?(:retry_count) ? payment.retry_count.to_i : 0
    needs_new_card = payment.respond_to?(:needs_new_card?) && payment.needs_new_card?
    decline_reason = payment.respond_to?(:decline_reason) ? payment.decline_reason.to_s.presence || "none" : "none"

    # Date fields — always return a string, never nil
    next_payment_date_str = next_payment_due&.in_time_zone&.strftime("%m/%d/%Y") || "N/A"
    next_payment_due_str  = next_payment_due&.in_time_zone&.iso8601 || "N/A"
    last_paid_str         = payment.paid_at&.in_time_zone&.iso8601 || "N/A"
    date_processed_str    = payment.paid_at&.in_time_zone&.iso8601 || Time.current.iso8601

    # Document URLs — always return a string
    financing_url  = agreement&.pdf&.attached? ? agreement.pdf.url : "N/A"
    engagement_url = agreement&.engagement_pdf&.attached? ? agreement.engagement_pdf.url : "N/A"

    {
      email:                   user.email.presence || "N/A",
      first_name:              user.first_name.presence || "N/A",
      last_name:               user.last_name.presence || "N/A",
      phone:                   user.phone.presence || "N/A",
      payment_type:            normalized_payment_type(plan, payment),
      payment_status:          status,
      status:                  status,
      trigger:                 status,
      firm_name:               resolve_firm_name(user),
      down_payment:            format_amount(down_payment),
      payment_amount:          format_amount(payment_amount),
      installment_amount:      format_amount(installment_amount),
      total_amount:            format_amount(total_amount),
      remaining_balance:       format_amount(remaining_balance),
      overdue:                 is_overdue ? "overdue" : "paying",
      next_payment_date:       next_payment_date_str,
      next_payment_due:        next_payment_due_str,
      last_paid:               last_paid_str,
      date_processed:          date_processed_str,
      login_magic_link:        generate_magic_link(user) || "N/A",
      financing_agreement_url: financing_url,
      engagement_letter_url:   engagement_url,
      retry_count:             retry_count,
      needs_new_card:          needs_new_card ? "yes" : "no",
      decline_reason:          decline_reason
    }
  end

  # Format monetary amounts as a 2-decimal string so GHL never receives a raw BigDecimal
  def format_amount(value)
    "%.2f" % value.to_d
  end

  def normalized_payment_type(plan, payment)
    return "Paid in full(PIF)" if payment.full_payment?
    return "Payment Plan" if plan.payment_plan_selected?

    "credit_card"
  end

  def generate_magic_link(user)
    LoginLinkService.new(user: user).generate_link
  rescue StandardError => e
    Rails.logger.warn("[GHL Payment Webhook Worker] Could not generate magic link for user_id=#{user.id}: #{e.message}")
    nil
  end

  def resolve_firm_name(user)
    # Always return the law firm name (non-Fund Forge). If the client only has a Fund Forge
    # record (direct Fund Forge client with no law firm association), default to Ironclad Law.
    user.firms.where.not(name: "Fund Forge").pick(:name) || "Ironclad Law"
  end

  # Returns true if the next payment due date has passed by at least 1 day (even 1 day late = overdue)
  def plan_overdue?(plan)
    due = plan.next_payment_at || plan.calculated_next_payment_at
    return false if due.nil?

    due.to_date < Time.current.to_date
  end
end
