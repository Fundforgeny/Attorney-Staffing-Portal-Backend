class Agreement < ApplicationRecord
	belongs_to :user
	belongs_to :plan

	has_one_attached :pdf
  has_one_attached :engagement_pdf
	has_one_attached :signature

	def self.ransackable_associations(auth_object = nil)
    %w[user plan]
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id user_id plan_id signed_at created_at updated_at pdf_attachment_id pdf_blob_id engagement_pdf_attachment_id engagement_pdf_blob_id signature_attachment_id signature_blob_id]
  end
end
