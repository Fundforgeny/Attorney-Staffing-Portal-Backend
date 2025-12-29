# app/models/firm_user.rb
class FirmUser < ApplicationRecord
  belongs_to :firm
  belongs_to :user

  enum :role, { member: 0, admin: 1 }
end
