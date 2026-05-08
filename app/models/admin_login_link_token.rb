class AdminLoginLinkToken < ApplicationRecord
  EXPIRATION_WINDOW = 15.minutes

  belongs_to :admin_user

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :usable, -> { where(used_at: nil).where("expires_at > ?", Time.current) }

  def expired?
    expires_at <= Time.current
  end

  def used?
    used_at.present?
  end
end
