ActiveAdmin.register User do
  permit_params :email, :password, :password_confirmation, :user_type

  controller do
    def scoped_collection
      super.where(user_type: User.user_types[:super_admin])
    end
  end

  index do
    selectable_column
    id_column
    column :email
    column :user_type
    column :created_at
    column :updated_at
    actions
  end

  filter :email
  filter :user_type
  filter :created_at

  form do |f|
    f.inputs do
      f.input :email
      f.input :user_type
      f.input :password
      f.input :password_confirmation
    end
    f.actions
  end
end
