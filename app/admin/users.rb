ActiveAdmin.register User, as: "Users" do
  permit_params :email, :first_name, :last_name, :user_type, :phone, :dob, :address_street, :city, :state, :country, :annual_salary, :contact_source, firm_ids: []

  # Remove password fields from edit form (handled separately)
  controller do
    def update
      if params[:user][:password].blank?
        params[:user].delete(:password)
        params[:user].delete(:password_confirmation)
      end
      super
    end
  end

  index do
    selectable_column
    id_column
    column :email
    column :first_name
    column :last_name
    column :user_type do |user|
      status_tag(user.user_type.to_s.humanize, class: user.user_type)
    end
    column :phone
    column :firm do |user|
      user.primary_firm&.name || "No Firm"
    end
    actions
  end

  show do
    attributes_table do
      row :id
      row :email
      row :first_name
      row :last_name
      row :user_type do |user|
        status_tag(user.user_type.to_s.humanize, class: user.user_type)
      end
      row :phone
      row :dob
      row :address_street
      row :city
      row :state
      row :country
      row :annual_salary
      row :contact_source
      row :firms do |user|
        user.firms.map(&:name).join(", ") || "No Firms"
      end
    end
  end

  filter :email
  filter :first_name
  filter :last_name
  filter :user_type, as: :select
  filter :phone
  filter :firms

  form do |f|
    f.inputs "User Information" do
      f.input :email
      f.input :first_name
      f.input :last_name
      f.input :user_type, as: :select, collection: User.user_types.keys.map { |type| [type.to_s.humanize, type] }
      f.input :phone
      f.input :dob, as: :date_picker
      f.input :address_street
      f.input :city
      f.input :state
      f.input :country
      f.input :annual_salary
      f.input :contact_source
      f.input :firm_ids, as: :select, collection: Firm.all.pluck(:name, :id)
    end
    
    f.inputs "Password (leave blank to keep current password)" do
      f.input :password
      f.input :password_confirmation
    end
    
    f.actions
  end

  # Custom action to reset password
  action_item :view, only: :show do
    link_to "Reset Password", reset_password_admin_user_path(resource), method: :patch, 
            data: { confirm: "Are you sure you want to reset this user's password?" }
  end

  member_action :reset_password, method: :patch do
    resource.update(password: SecureRandom.hex(8), password_confirmation: nil)
    redirect_to admin_user_path(resource), notice: "Password has been reset. New password: #{resource.password}"
  end
end
