# app/models/firm_user.rb
class FirmUser < ApplicationRecord
  belongs_to :firm
  belongs_to :user
end
