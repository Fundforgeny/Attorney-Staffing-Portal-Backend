ActiveAdmin.register Firm do
  permit_params :name, :location_id, :description, :size, :logo, :primary_color, :secondary_color, :ghl_api_key

  index do
    selectable_column
    id_column
    column :name
    column :location_id
    column :ghl_api_key
    column :logo do |firm|
      if firm.logo.attached?
        image_tag url_for(firm.logo), width: 50, height: 50
      else
        "No logo"
      end
    end
    column :primary_color
    column :secondary_color
    column :created_at
    column :users_count do |firm|
      firm.users.count
    end
    actions
  end

  show do
    attributes_table do
      row :id
      row :name
      row :location_id
      row :ghl_api_key
      row :description do |firm|
      content_tag :div,
                  firm.description,
                  style: "max-width: 300px;
                          max-height: 80px;
                          overflow-y: auto;
                          white-space: pre-wrap;
                          padding: 6px;
                          border: 1px solid #ddd;
                          border-radius: 4px;
                          background-color: #fafafa;"
    end
      row :logo do |firm|
        if firm.logo.attached?
          image_tag url_for(firm.logo), width: 50, height: 50
        else
          "No logo"
        end
      end
      row :primary_color
      row :secondary_color
      row :created_at
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

  form do |f|
    f.inputs "Firm Information" do
      f.input :name
      f.input :location_id
      f.input :ghl_api_key
      f.input :description, as: :text
      f.input :primary_color
      f.input :secondary_color
      f.input :logo, as: :file
    end
    f.actions
  end

  # Batch actions
  batch_action :export_to_csv do |ids|
    firms = Firm.where(id: ids)
    csv_data = CSV.generate do |csv|
      csv << ["Name", "Location ID", "GHL API Key", "Description", "Logo", "Primary Color", "Secondary Color"]
      firms.each do |firm|
        csv << [firm.name, firm.location_id, firm.ghl_api_key, firm.description, firm.logo.attached? ? firm.logo.url : "No logo", firm.primary_color, firm.secondary_color]
      end
    end
    send_data csv_data, filename: "firms_#{Date.current}.csv"
  end
end
