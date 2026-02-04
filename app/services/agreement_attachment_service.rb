# app/services/agreement_attachment_service.rb
class AgreementAttachmentService
  def initialize(agreement)
    @agreement = agreement
    @user = agreement.user
    @plan = agreement.plan
    @pdf_generator = PdfGeneratorService.new(@user, @plan)
  end

  def attach_agreements
    attach_fund_forge_agreement if needs_fund_forge?
    attach_engagement_agreement if needs_engagement?
  end

  private

  def needs_fund_forge?
    @user.has_fund_forge_firm? || @user.firms.empty?
  end

  def needs_engagement?
    @user.has_other_firms?
  end

  def attach_fund_forge_agreement
    path = @pdf_generator.generate_fund_forge
    @agreement.pdf.attach(
      io: File.open(path),
      filename: "fund_forge_agreement_#{@plan.id}.pdf",
      content_type: "application/pdf"
    )
    File.delete(path) if File.exist?(path)
  end

  def attach_engagement_agreement
    path = @pdf_generator.generate_engagement
    @agreement.engagement_pdf.attach(
      io: File.open(path),
      filename: "engagement_agreement_#{@plan.id}.pdf",
      content_type: "application/pdf"
    )
    File.delete(path) if File.exist?(path)
  end
end
