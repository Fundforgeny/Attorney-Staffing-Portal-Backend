ActiveAdmin.register User do
  # Permit Params
  permit_params :email, :first_name, :last_name, :user_type, :phone, :dob, 
                :address_street, :city, :state, :country, :annual_salary, 
                :contact_source, :password, :password_confirmation, 
                :firm_id, firm_ids: []

  # Filters
  filter :id
  filter :email
  filter :first_name
  filter :last_name
  filter :firms, as: :select, collection: Firm.all
  filter :user_type, as: :select, collection: User.user_types.keys.map { |type| [type.to_s.humanize, type] }
  filter :phone
  filter :created_at 
  # Views
  index do
    selectable_column
    id_column
    column :email
    column :first_name
    column :last_name
    column :user_type do |user|
      status_tag user.user_type
    end
    column :phone
    column :firms do |user|
      user.firms&.map(&:name).join(", ") || "No Firm"
    end
    
    actions
  end

  # Show
  show do
    attributes_table do
      row :id
      row :first_name
      row :last_name
      row :email
      row :user_type do |user|
        status_tag user.user_type
      end
      row :phone
      row :is_verfied
      row :address_street
      row :city
      row :state
      row :postal_code
      row :country
    
      row :Firms do |user|
        user.firms&.map(&:name).join(", ") || "No Firm Assigned"
      end
      row :annual_salary
    end

    panel "Payment Methods" do
      cards = user.payment_methods.ordered_for_user
      if cards.any?
        table_for cards do
          column("Brand")   { |c| c.card_brand&.upcase || "CARD" }
          column("Last 4")  { |c| "••••#{c.last4}" }
          column("Expires") { |c| "#{c.exp_month}/#{c.exp_year}" }
          column("Name")    { |c| c.cardholder_name }
          column("Default") { |c| c.is_default? ? status_tag("Default", class: "status_tag ok") : "—" }
          column("Vault")   { |c| c.vault_token.present? ? status_tag("Vaulted", class: "status_tag ok") : status_tag("Missing", class: "status_tag error") }
          column :created_at
        end
      else
        para "No payment methods added"
      end
    end

    panel "Plans for this User" do
      if user.plans.any?
        table_for user.plans.order(created_at: :desc) do
          column("Name")    { |plan| link_to plan.name, admin_plan_path(plan) }
          column :duration
          column("Total")   { |plan| number_to_currency(plan.total_payment) }
          column("Monthly") { |plan| number_to_currency(plan.monthly_payment) }
          column("Down")    { |plan| number_to_currency(plan.down_payment) }
          column :status do |plan|
            status_tag plan.status
          end
          column("Next Payment") { |plan| plan.next_payment_at&.strftime("%b %-d, %Y") || "—" }
          column :created_at
          column("Actions")  { |plan| link_to "View Plan →", admin_plan_path(plan), class: "button" }
        end
      else
        para "No plans found"
      end
    end
  end

  # Form
  form do |f|
    f.inputs "Basic Information" do
      f.input :email, label: "Email", input_html: { autocomplete: "new-email" }
      f.input :first_name
      f.input :last_name
      f.input :user_type, as: :select, collection: User.user_types.keys.map { |type| [type.to_s.humanize, type] }
      f.input :phone
      f.input :dob, as: :date_picker
    end

    f.inputs "Location Details" do
      f.input :address_street
      f.input :city
      f.input :state
      f.input :country
    end

    f.inputs "Professional Info" do
      f.input :annual_salary
      f.input :contact_source
      f.input :firms, as: :select, multiple: true, collection: Firm.all, include_blank: "No Firm"
    end

    f.inputs "Security" do
      f.input :password, 
              hint: "Leave blank to keep current password",
              input_html: { autocomplete: "new-password" }
      f.input :password_confirmation, label: "Password confirmation",
                                      input_html: { autocomplete: "new-password" }
    end
    f.actions
  end
end
