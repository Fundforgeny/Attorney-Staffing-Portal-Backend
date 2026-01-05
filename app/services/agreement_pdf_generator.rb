class AgreementPdfGenerator
  TEMPLATE_PATH = Rails.root.join("app/assets/pdfs/fund_forge_agreement.pdf")

  def initialize(user, plan)
    @user = user
    @plan = plan
    @pdftk = PdfForms.new('/usr/bin/pdftk')
  end

  def generate
    raise "Template not found at #{TEMPLATE_PATH}" unless File.exist?(TEMPLATE_PATH)

    file_path = Rails.root.join(
      "tmp",
      "fund_forge_agreement_#{@user.id}_#{@plan.id}_#{Time.current.to_i}.pdf"
    )

    fields = {
      'customer_name'             => full_name,
      'customer_email'            => @user.email,
      'customer_address'          => @user.address_street || 'N/A',
      'monthly_payment'           => formatted(@plan.monthly_payment),
      'down_payment'              => formatted(@plan.down_payment),
      'annual_percentage_rate'    => "19%",
      'interest_rate'             => "#{apr_rate}%",
      'amount_financed'           => formatted(amount_financed),
      'total_interest'            => formatted(@plan.total_interest_amount),
      'total_payment_plan_amount' => formatted(@plan.total_payment),
      'no_of_payments'            => @plan.duration.to_s,
      'duration'                  => @plan.duration ? "Monthly" : "One Time Payment",
      'loan_term_months'          => @plan.duration.to_s,
      'current_date'              => Date.current.strftime("%m/%d/%Y"),
      'apr'                       => "19%",
      'monthly_payments'          => "#{formatted(@plan.monthly_payment)} x #{@plan.duration}",
      'financed_charge'           => formatted(@plan.total_interest_amount),
      'total_of_payments'         => formatted(@plan.total_payment),
    }

    @pdftk.fill_form(TEMPLATE_PATH.to_s, file_path.to_s, fields, flatten: true)
    file_path.to_s
  end

  private

  def full_name
    "#{@user.first_name} #{@user.last_name}".strip
  end

  def amount_financed
    (@plan.total_payment - @plan.down_payment).to_f
  end

  def apr_rate
    return "0.00" if amount_financed.zero?
    ((@plan.total_interest_amount / amount_financed) * 100).round(2)
  end

  def formatted(amount)
    ActionController::Base.helpers.number_to_currency(amount || 0, precision: 2)
  end
end
