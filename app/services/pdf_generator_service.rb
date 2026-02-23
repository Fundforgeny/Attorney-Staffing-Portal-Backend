# app/services/pdf_generator_service.rb
class PdfGeneratorService
  FUND_FORGE_TEMPLATE = Rails.root.join("app/assets/pdfs/fund_forge_agreement.pdf")
  ENGAGEMENT_TEMPLATE = Rails.root.join("app/assets/pdfs/engagement_agreement.pdf")

  def initialize(user, plan)
    @user = user
    @plan = plan
    @pdftk = PdfForms.new('/usr/bin/pdftk')
  end

  # Method 1: Fund Forge PDF
  def generate_fund_forge
    raise "Template not found" unless File.exist?(FUND_FORGE_TEMPLATE)

    output_path = temp_path("fund_forge")
    fields = {
      'customer_name'             => full_name,
      'customer_email'            => @user.email,
      'customer_address'          => @user.address_street || 'N/A',
      'monthly_payment'           => formatted(@plan.monthly_payment),
      'down_payment'              => formatted(@plan.down_payment),
      'annual_percentage_rate'    => "#{administration_fee_percentage}%",
      'interest_rate'             => "#{administration_fee_percentage}%",
      'amount_financed'           => formatted(amount_financed),
      'total_interest'            => formatted(@plan.administration_fee_amount),
      'total_payment_plan_amount' => formatted(@plan.total_payment_plan_amount),
      'no_of_payments'            => @plan.duration.to_s,
      'duration'                  => @plan.duration ? "Monthly" : "One Time Payment",
      'loan_term_months'          => @plan.duration.to_s,
      'current_date'              => Date.current.strftime("%m/%d/%Y"),
      'apr'                       => "#{administration_fee_percentage}%",
      'monthly_payments'          => "#{formatted(@plan.monthly_payment)} x #{@plan.duration}",
      'financed_charge'           => formatted(@plan.administration_fee_amount),
      'total_of_payments'         => formatted(@plan.total_payment_plan_amount),
    }

    @pdftk.fill_form(FUND_FORGE_TEMPLATE.to_s, output_path, fields, flatten: true)
    output_path
  end

  # Method 2: Engagement PDF
  def generate_engagement
    raise "Template not found" unless File.exist?(ENGAGEMENT_TEMPLATE)

    output_path = temp_path("engagement")
    fields = {
      'contact_name'    => full_name,
      'contact_email'   => @user.email,
      'retainer_amount' => formatted(@plan.down_payment),
      'date'            => Date.current.strftime("%m/%d/%Y"),
    }

    @pdftk.fill_form(ENGAGEMENT_TEMPLATE.to_s, output_path, fields, flatten: true)
    output_path
  end

  private

  def temp_path(prefix)
    Rails.root.join("tmp", "#{prefix}_#{@user.id}_#{@plan.id}_#{Time.current.to_i}.pdf").to_s
  end

  def full_name
    "#{@user.first_name} #{@user.last_name}".strip
  end

  def amount_financed
    (@plan.total_payment - (@plan.down_payment || 0)).to_f
  end

  def administration_fee_percentage
    @plan.payment_plan_selected? ? @plan.administration_fee_percentage : 0
  end

  def formatted(amount)
    ActionController::Base.helpers.number_to_currency(amount || 0, precision: 2)
  end
end
