# app/services/agreement_attachment_service.rb
class AgreementAttachmentService
  def initialize(agreement)
    @agreement = agreement
    @user = agreement.user
    @plan = agreement.plan
    @pdf_generator = PdfGeneratorService.new(@user, @plan)
  rescue StandardError => e
    # If pdftk is missing, skip PDF generation without failing the request
    Rails.logger.error("PDF generator unavailable for Agreement ##{@agreement.id}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if Rails.env.development?
    @pdf_generator = nil
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
    return unless @pdf_generator

    path = @pdf_generator.generate_fund_forge
    @agreement.pdf.attach(
      io: File.open(path),
      filename: "fund_forge_agreement_#{@plan.id}.pdf",
      content_type: "application/pdf"
    )
    File.delete(path) if File.exist?(path)
  end

  def attach_engagement_agreement
    return unless @pdf_generator

    path = @pdf_generator.generate_engagement
    @agreement.engagement_pdf.attach(
      io: File.open(path),
      filename: "engagement_agreement_#{@plan.id}.pdf",
      content_type: "application/pdf"
    )
    File.delete(path) if File.exist?(path)
  end
end
