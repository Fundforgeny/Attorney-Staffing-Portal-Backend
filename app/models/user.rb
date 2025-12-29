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
  belongs_to :firm, optional: true

  # Validations
  validates :email, presence: true, uniqueness: true


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
end