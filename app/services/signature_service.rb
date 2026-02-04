# app/services/signature_service.rb
class SignatureService
  def initialize(user, agreement, signature_data)
    @user = user
    @agreement = agreement
    @signature_data = signature_data
  end

  def save_signature
    validate_ownership
    validate_signature_format
    
    decoded_data = decode_signature
    temp_file = create_temp_file(decoded_data)
    
    begin
      attach_signature(temp_file)
      process_signed_agreement
      update_agreement_status
      generate_response_data
    ensure
      cleanup_temp_file(temp_file)
    end
  end

  private

  def validate_ownership
    unless @agreement.plan.user_id == @user.id
      raise ArgumentError, "Agreement does not belong to user"
    end
  end

  def validate_signature_format
    unless @signature_data.is_a?(String) && @signature_data.start_with?('data:image/png;base64,')
      raise ArgumentError, "Invalid signature format. Expected base64 encoded PNG"
    end
  end

  def decode_signature
    base64_data = @signature_data.sub(/^data:image\/png;base64,/, '')
    Base64.strict_decode64(base64_data)
  rescue Base64::DecodeError => e
    raise ArgumentError, "Invalid base64 encoding in signature"
  end

  def create_temp_file(decoded_data)
    temp_file = Tempfile.new(['signature_', '.png'])
    temp_file.binmode
    temp_file.write(decoded_data)
    temp_file.rewind
    temp_file
  end

  def attach_signature(temp_file)
    filename = "signature_#{@agreement.id}_#{Time.current.to_i}.png"
    @agreement.signature.attach(
      io: temp_file,
      filename: filename,
      content_type: "image/png"
    )
    @filename = filename
  end

  def process_signed_agreement
    pdf_coordinates = {
      "pdf" => [130, 430],
      "engagement_pdf" => [130, 670]
    }
    
    ::ProcessSignedAgreementWorker.perform_async(
      @agreement.id, 
      @agreement.signature.blob.id, 
      pdf_coordinates
    )
  end

  def update_agreement_status
    @agreement.update!(signed_at: Time.current) if @agreement.signed_at.blank?
  end

  def generate_response_data
    signature_url = Rails.application.routes.url_helpers.rails_blob_url(@agreement.signature, only_path: true)
    
    {
      agreement_id: @agreement.id,
      signature_url: signature_url,
      signature_filename: @filename,
      signed_at: @agreement.signed_at
    }
  end

  def cleanup_temp_file(temp_file)
    temp_file&.close
    temp_file&.unlink
  end
end
