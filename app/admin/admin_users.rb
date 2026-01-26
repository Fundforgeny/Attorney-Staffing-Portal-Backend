ActiveAdmin.register AdminUser do
  permit_params :email, :password, :password_confirmation
  
  filter :email
  filter :first_name
  filter :last_name
  filter :created_at

  index do
    selectable_column
    id_column
    column :first_name
    column :last_name
    column :email
    column :contact_number
    column :created_at
    column :updated_at
    actions
  end

  form do |f|
    f.inputs do
      f.input :first_name
      f.input :last_name
      f.input :email
      f.input :contact_number
      f.input :password
      f.input :password_confirmation
    end
    f.actions
  end
end
