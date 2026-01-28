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
  has_many :payment_methods, dependent: :destroy
  has_many :plans, dependent: :destroy
  has_many :agreements, dependent: :destroy

  # Callbacks
  before_create :sync_with_ghl_accounts
  before_save :normalize_email

  # Validations
  validates :email, presence: true, uniqueness: true

  # Define which attributes are searchable by Ransack
  def self.ransackable_attributes(auth_object = nil)
    column_names + _ransackers.keys
  end

  # Define which associations are searchable by Ransack
  def self.ransackable_associations(auth_object = nil)
    ["attorney_profile", "client_profile", "firm_users", "firm", "firms", "payment_methods", "plans", "agreements"]
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

  def has_fund_forge_firm?
    firms.fund_forge.exists?
  end

  def has_other_firms?
    (firms - Firm.fund_forge).any?
  end

  def split_name(full_name)
    return ["", ""] if full_name.blank?
    
    parts = full_name.split(" ", 2)
    first_name = parts[0] || ""
    last_name = parts[1] || ""
    [first_name, last_name]
  end

  private

  def normalize_email
    self.email = email&.downcase&.strip if email_changed?
  end

  def sync_with_ghl_accounts
    SearchGhlContactsWorker.perform_async(id)
  end

end
