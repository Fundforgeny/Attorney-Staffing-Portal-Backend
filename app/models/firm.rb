class Firm < ApplicationRecord
  has_many :firm_users, dependent: :destroy
  has_many :users, through: :firm_users

  has_many :attorney_profiles
  has_many :client_profiles
end
