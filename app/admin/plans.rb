ActiveAdmin.register Plan do
  permit_params :name,:duration,:total_payment,:total_interest_amount,:monthly_payment,:monthly_interest_amount,:down_payment,:status,:user_id
  
  filter :name
  filter :user
  filter :duration
  filter :total_payment
  filter :monthly_payment
  filter :status, as: :select, collection: Plan.statuses.keys.map { |status| [status.to_s.humanize, status] }
  filter :created_at

  index do
    selectable_column
    id_column
    column :name
    column :user
    column :duration
    column :total_payment
    column :monthly_payment
    column :status
    column :created_at
    actions
  end

  show do
    attributes_table do
      row :id
      row :name
      row :user
      row :duration
      row :total_payment
      row :total_interest_amount
      row :monthly_payment
      row :monthly_interest_amount
      row :down_payment
      row :status do |plan|
        status_tag plan.status
      end
      row :created_at
      row :updated_at
    end

    panel "Payments for this Plan" do
      payments = Payment.where(plan_id: resource.id).order(created_at: :desc)

      if payments.any?
        table_for payments do
          column :user_id
          column :payment_amount
          column :transaction_fee
          column :total_payment_including_fee
          column :status do |payment|
            status_tag payment.status
          end
          column :paid_at
          column :created_at
        end
      else
        para "No payments found for this plan"
      end
    end
  end

  form do |f|
    f.semantic_errors
    f.inputs "Plan Details" do
      f.input :user
      f.input :name
      f.input :duration
      f.input :total_payment
      f.input :total_interest_amount
      f.input :monthly_payment
      f.input :monthly_interest_amount
      f.input :down_payment
      f.input :status, as: :select, collection: Plan.statuses.keys.map { |status| [status.to_s.humanize, status] }
    end
    f.actions
  end
end
