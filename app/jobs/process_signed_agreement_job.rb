# app/jobs/process_signed_agreement_job.rb
class ProcessSignedAgreementJob < ApplicationJob
  queue_as :default

  def perform(agreement_id, signature_blob_id, coordinates_hash)
    agreement = Agreement.find(agreement_id)
    signature_blob = ActiveStorage::Blob.find(signature_blob_id)
    
    # Create a local tempfile for the signature image so Prawn can read it
    temp_signature = Tempfile.new(['sig', '.png'], binmode: true)
    temp_signature.write(signature_blob.download)
    temp_signature.rewind

    ["pdf", "engagement_pdf"].each do |pdf_key|
      attachment = agreement.send(pdf_key)
      next unless attachment.attached?

      # Get coordinates for this specific PDF or use a default
      coords = coordinates_hash[pdf_key] || [400, 150]

      # 1. Download unsigned PDF from S3
      unsigned_binary = attachment.download
      
      # 2. Stamp it using the Service
      signed_binary = PdfSignatureService.add_signature(unsigned_binary, temp_signature.path, coords)

      # 3. Attach signed version (Overwrites the old one on S3)
      attachment.attach(
        io: StringIO.new(signed_binary),
        filename: "signed_#{attachment.filename}",
        content_type: "application/pdf"
      )
    end
  ensure
    # Cleanup local temp files
    temp_signature&.close
    temp_signature&.unlink
  end
end