# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable,
         :confirmable,
         :jwt_authenticatable, jwt_revocation_strategy: JwtDenylist

  enum :user_type, { client: 0, attorney: 1, super_admin: 2 }

  # Associations
  has_many :firm_users, dependent: :destroy
  has_many :firms, through: :firm_users
  has_one :attorney_profile, dependent: :destroy
  has_one :client_profile, dependent: :destroy
  has_one :payment_method, dependent: :destroy
  belongs_to :firm, optional: true
  has_many :plans, dependent: :destroy
  has_many :agreements

  # Validations
  validates :email, presence: true, uniqueness: true

  # Define which attributes are searchable by Ransack
  def self.ransackable_attributes(auth_object = nil)
    ["address_street", "annual_salary", "city", "confirmation_sent_at", "confirmation_token", "confirmed_at", "contact_source", "country", "current_sign_in_at", "current_sign_in_ip", "dob", "email", "encrypted_password", "first_name", "id", "id_value", "is_verfied", "last_name", "last_sign_in_at", "last_sign_in_ip", "payment_method_id", "phone", "postal_code", "remember_created_at", "reset_password_sent_at", "reset_password_token", "sign_in_count", "state", "time_zone", "unconfirmed_email", "user_type", "verification_status"]
  end

  # Define which associations are searchable by Ransack
  def self.ransackable_associations(auth_object = nil)
    ["attorney_profile", "client_profile", "firm_users", "firms", "payment_method"]
  end

  def full_name
    "#{first_name} #{last_name}".strip.presence || email
  end

  def self.devise_name
    :user
  end

  def super_admin?
    user_type == "super_admin"
  end

  def attorney?
    user_type == "attorney" || attorney_profile.present?
  end

  def client?
    user_type == "client" || client_profile.present?
  end

  def profile
    attorney_profile || client_profile
  end

  # Get the primary firm (first associated firm)
  def primary_firm
    firms.first
  end
end