# app/models/client_profile.rb
class ClientProfile < ApplicationRecord
  belongs_to :user
  belongs_to :firm, optional: true
end