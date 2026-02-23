ActiveAdmin.register Payment do
  menu false

  permit_params :user_id, :plan_id, :payment_method_id,:payment_type, :payment_amount, :status, :scheduled_at, :paid_at,:total_payment_including_fee, :transaction_fee

  # Add custom scopes for filtering - succeeded will be default
  scope :all
  scope :succeeded, default: true
  scope :pending
  scope :processing
  scope :failed

  # Filters
  filter :user
  filter :plan
  filter :payment_type, as: :select, collection: Payment.payment_types.keys.map { |type| [type.to_s.humanize, type] }
  filter :status, as: :select, collection: Payment.statuses.keys.map { |status| [status.to_s.humanize, status] }
  filter :payment_amount
  filter :scheduled_at
  filter :paid_at
  filter :created_at

  index do
    selectable_column
    id_column

    column :user
    column :plan
    column :payment_type
    column :payment_amount
    column("Administration Fee") { |payment| number_to_currency(payment.transaction_fee || 0) }
    column("Total Charged") { |payment| number_to_currency(payment.total_payment_including_fee || 0) }
    column :status do |payment|
      status_tag payment.status
    end
    column :scheduled_at
    column :paid_at
    column :created_at

    actions
  end

  show do
    attributes_table do
      row :id
      row :user
      row :plan
      row :payment_type
      row :payment_amount
      row("Administration Fee") { |payment| number_to_currency(payment.transaction_fee || 0) }
      row("Total Charged") { |payment| number_to_currency(payment.total_payment_including_fee || 0) }
      row :status do |payment|
        status_tag payment.status
      end
      row :scheduled_at
      row :paid_at
      row :created_at
    end
  end

  form do |f|
    f.inputs "Payment Details" do
      f.input :user
      f.input :plan
      f.input :payment_type
      f.input :payment_amount
      f.input :transaction_fee, label: "Administration Fee"
      f.input :total_payment_including_fee, label: "Total Charged"
      f.input :status
      f.input :scheduled_at, as: :datetime_picker
      f.input :paid_at, as: :datetime_picker
    end
    f.actions
  end
end
