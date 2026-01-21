class ProcessSignedAgreementWorker
  include Sidekiq::Worker
  sidekiq_options retry: 5

  def perform(agreement_id, signature_blob_id, coordinates_hash)
    agreement = Agreement.find(agreement_id)
    signature_blob = ActiveStorage::Blob.find(signature_blob_id)
    
    # Download the signature image
    temp_signature = Tempfile.new(['sig', '.png'], binmode: true)
    temp_signature.write(signature_blob.download)
    temp_signature.rewind

    # Loop through the attachments
    ["pdf", "engagement_pdf"].each do |pdf_key|
      attachment = agreement.send(pdf_key)
      next unless attachment.attached?

      # Use coordinates from hash (keys will be strings in Sidekiq)
      coords = coordinates_hash[pdf_key] || [140, 540]

      # Stamp using the Service
      unsigned_binary = attachment.download
      signed_binary = PdfSignatureService.add_signature(unsigned_binary, temp_signature.path, coords)

      # Overwrite the unsigned PDF on S3
      attachment.attach(
        io: StringIO.new(signed_binary),
        filename: "signed_#{attachment.filename}",
        content_type: "application/pdf"
      )
    end
  ensure
    temp_signature&.close
    temp_signature&.unlink
  end
end
