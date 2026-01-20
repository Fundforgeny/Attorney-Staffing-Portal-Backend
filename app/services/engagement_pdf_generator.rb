class EngagementPdfGenerator
  TEMPLATE_PATH = Rails.root.join("app/assets/pdfs/engagement_agreement.pdf")

  def initialize(user, plan)
    @user = user
    @plan = plan
    @pdftk = PdfForms.new('/usr/bin/pdftk')
  end

  def generate
    raise "Template not found at #{TEMPLATE_PATH}" unless File.exist?(TEMPLATE_PATH)

    file_path = Rails.root.join(
      "tmp",
      "engagement_agreement_#{@user.id}_#{@plan.id}_#{Time.current.to_i}.pdf"
    )

    fields = {
      'contact_name'                 => full_name,
      'contact_email'                => @user.email,
      'retainer_amount'              => formatted(@plan.down_payment),
      'date'                         => Date.current.strftime("%m/%d/%Y"),
    }

    @pdftk.fill_form(TEMPLATE_PATH.to_s, file_path.to_s, fields, flatten: true)
    file_path.to_s
  end

  private

  def full_name
    "#{@user.first_name} #{@user.last_name}".strip
  end

  def formatted(amount)
    ActionController::Base.helpers.number_to_currency(amount || 0, precision: 2)
  end
end
