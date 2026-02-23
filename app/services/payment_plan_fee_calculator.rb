class PaymentPlanFeeCalculator
  FEE_NAME = "Fund Forge Payment Plan Administration Fee".freeze
  FEE_PERCENTAGE = BigDecimal("0.04")

  def self.plan_selected?(selected_payment_plan:, duration:)
    return ActiveModel::Type::Boolean.new.cast(selected_payment_plan) unless selected_payment_plan.nil?

    duration.to_i.positive?
  end

  def initialize(base_amount:, selected_payment_plan:)
    @base_amount = BigDecimal(base_amount.to_s)
    @selected_payment_plan = selected_payment_plan
  end

  def fee_amount
    return BigDecimal("0") unless @selected_payment_plan

    (@base_amount * FEE_PERCENTAGE).round(2)
  end

  def total_amount
    (@base_amount + fee_amount).round(2)
  end
end


