# app/models/attorney_profile.rb
class AttorneyProfile < ApplicationRecord
  belongs_to :user
  belongs_to :firm
end