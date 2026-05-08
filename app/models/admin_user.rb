class AdminUser < ApplicationRecord
  # Macros / DSL-style declarations

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable,
         :recoverable, :rememberable, :validatable

  has_many :admin_login_link_tokens, dependent: :destroy

  enum :role, {
    fund_forge_admin: 0,
    fund_forge_refunds: 1,
    fund_forge_readonly: 2
  }

  before_validation :normalize_email

  # Validations

  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :contact_number, phone: true, presence: true

  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }

  # Class methods

  def self.ransackable_attributes(auth_object = nil)
    [
      "id", "email",
      "first_name", "last_name", "contact_number", "role",
      "created_at", "updated_at"
    ]
  end

  # Public Methods

  def formatted_phone
    parsed_phone = Phonelib.parse(contact_number)
    return contact_number if parsed_phone.invalid?

    formatted =
      if parsed_phone.country_code == "1" # NANP
        parsed_phone.full_national # (415) 555-2671;123
      else
        parsed_phone.full_international # +44 20 7183 8750
      end

    formatted.gsub!(";", " x") # (415) 555-2671 x123

    formatted
  end

  def full_access?
    fund_forge_admin?
  end

  def can_refund_payments?
    fund_forge_admin? || fund_forge_refunds?
  end

  private

  def normalize_email
    self.email = email&.downcase&.strip if email_changed?
  end
end
