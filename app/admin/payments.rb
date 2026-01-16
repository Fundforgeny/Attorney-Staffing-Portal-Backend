ActiveAdmin.register Payment do
  permit_params :user_id, :plan_id, :payment_method_id,:payment_type, :payment_amount, :status, :scheduled_at, :paid_at,:total_payment_including_fee, :transaction_fee

  index do
    selectable_column
    id_column

    column :user
    column :plan
    column :payment_method
    column :payment_type
    column :payment_amount
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
      row :payment_method
      row :payment_type
      row :payment_amount
      row :total_payment_including_fee
      row :transaction_fee
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
      f.input :payment_method
      f.input :payment_type
      f.input :payment_amount
      f.input :total_payment_including_fee
      f.input :transaction_fee
      f.input :status
      f.input :scheduled_at, as: :datetime_picker
      f.input :paid_at, as: :datetime_picker
    end
    f.actions
  end
end
