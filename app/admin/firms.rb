ActiveAdmin.register Firm do
  permit_params :name, :address_street, :city, :state, :country, :phone, :email, :website, :description, :industry, :size

  index do
    selectable_column
    id_column
    column :name
    column :industry
    column :size
    column :city
    column :state
    column :phone
    column :users_count do |firm|
      firm.users.count
    end
    actions
  end

  show do
    attributes_table do
      row :id
      row :name
      row :address_street
      row :city
      row :state
      row :country
      row :phone
      row :email
      row :website
      row :description
      row :industry
      row :size
      row :users_count do
        resource.users.count
      end
    end

    panel "Users in this Firm" do
      table_for resource.users do
        column :id
        column :email
        column :first_name
        column :last_name
        column :user_type
        column "" do |user|
          link_to "View", admin_user_path(user)
        end
      end
    end
  end

  filter :name
  filter :industry
  filter :size
  filter :city
  filter :state

  form do |f|
    f.inputs "Firm Information" do
      f.input :name
      f.input :address_street
      f.input :city
      f.input :state
      f.input :country
      f.input :phone
      f.input :email
      f.input :website
      f.input :description, as: :text
      f.input :industry
      f.input :size, as: :select, collection: ["1-10", "11-50", "51-200", "201-500", "500+"]
    end
    f.actions
  end

  # Batch actions
  batch_action :export_to_csv do |ids|
    firms = Firm.where(id: ids)
    csv_data = CSV.generate do |csv|
      csv << ["Name", "Industry", "Size", "City", "State", "Phone", "Email"]
      firms.each do |firm|
        csv << [firm.name, firm.industry, firm.size, firm.city, firm.state, firm.phone, firm.email]
      end
    end
    
    send_data csv_data, filename: "firms_#{Date.current}.csv"
  end
end
