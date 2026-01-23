# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable,
         :confirmable,
         :jwt_authenticatable, jwt_revocation_strategy: JwtDenylist

  enum :user_type, { client: 0, attorney: 1 }

  # Associations
  has_many :firm_users, dependent: :destroy
  has_many :firms, through: :firm_users
  belongs_to :firm, optional: true
  has_one :attorney_profile, dependent: :destroy
  has_one :client_profile, dependent: :destroy
  has_one :payment_method, dependent: :destroy
  has_many :plans, dependent: :destroy
  has_many :agreements, dependent: :destroy

  # Callbacks
  after_create_commit :sync_with_ghl_accounts

  # Validations
  validates :email, presence: true, uniqueness: true

  # Define which attributes are searchable by Ransack
  def self.ransackable_attributes(auth_object = nil)
    column_names + _ransackers.keys
  end

  # Define which associations are searchable by Ransack
  def self.ransackable_associations(auth_object = nil)
    ["attorney_profile", "client_profile", "firm_users", "firm", "firms", "payment_method", "plans", "agreements"]
  end

  # Custom ransacker for firms association
  ransacker :firms do |parent|
    Arel::Table.new(User.table_name).from(
      User.joins(:firms).where(firms: { id: parent }).select(:id).arel.exists.not
    )
  end

  def full_name
    "#{first_name} #{last_name}".strip.presence || email
  end

  def self.devise_name
    :user
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

  private

  def sync_with_ghl_accounts
    SearchGhlContactsWorker.perform_async(id)
  end

end
