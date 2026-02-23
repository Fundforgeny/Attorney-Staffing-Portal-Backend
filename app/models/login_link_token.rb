class LoginLinkToken < ApplicationRecord
  EXPIRATION_WINDOW = 15.minutes

  belongs_to :user

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

