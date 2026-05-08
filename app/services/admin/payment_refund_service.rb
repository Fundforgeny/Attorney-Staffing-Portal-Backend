module Admin
  class PaymentRefundService
    def initialize(payment:, admin_user:, amount: nil, reason: nil)
      @payment = payment
      @admin_user = admin_user
      @amount = parse_amount(amount)
      @reason = reason.to_s.strip
      @client = Spreedly::Client.new
    end

    def call
      validate_inputs!

      refund_amount = requested_amount
      transaction = refund!(refund_amount)

      Payment.transaction do
        payment.lock!
        payment.update!(
          refunded_amount: payment.refunded_amount.to_d + refund_amount,
          refund_transaction_id: transaction["token"].presence || payment.refund_transaction_id,
          refunded_at: Time.current,
          last_refund_reason: reason.presence || payment.last_refund_reason
        )
      end

      payment
    rescue Spreedly::Error => e
      raise StandardError, extract_error_message(e.payload)
    end

    private

    attr_reader :payment, :admin_user, :amount, :reason, :client

    def validate_inputs!
      raise ArgumentError, "Only succeeded payments can be refunded." unless payment.succeeded?
      raise ArgumentError, "Payment is missing the original transaction token." if payment.charge_id.blank?
      raise ArgumentError, "This payment is already fully refunded." if refundable_amount <= 0
      raise ArgumentError, "Refund amount must be greater than 0." if requested_amount <= 0
      raise ArgumentError, "Refund amount exceeds the remaining refundable balance." if requested_amount > refundable_amount
    end

    def requested_amount
      amount.presence || refundable_amount
    end

    def refundable_amount
      payment.refundable_amount
    end

    def refund!(refund_amount)
      payload = {
        transaction: {
          amount: (refund_amount * 100).to_i,
          currency_code: "USD",
          description: refund_description
        }.compact
      }

      response = client.post("/transactions/#{payment.charge_id}/credit.json", body: payload)
      response.fetch("transaction")
    end

    def refund_description
      base = "Admin refund for payment ##{payment.id}"
      return base if reason.blank?

      "#{base}: #{reason}"
    end

    def extract_error_message(payload)
      transaction = payload.is_a?(Hash) ? payload["transaction"] : nil
      transaction&.dig("message").presence ||
        payload&.dig("error", "message").presence ||
        "Refund failed"
    end

    def parse_amount(value)
      return nil if value.nil? || value.to_s.strip.blank?

      BigDecimal(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
