ActiveAdmin.register Agreement do
  permit_params :user_id, :plan_id, :signed_at

  index do
    selectable_column
    id_column
    column :user
    column :plan
    column "PDF" do |agreement|
      if agreement.pdf.attached?
        link_to "View PDF",rails_blob_path(agreement.pdf, disposition: "attachment"),  target: "_blank"
      else
        status_tag "No PDF", class: "warning"
      end
    end
    column :signed_at
    column :created_at
    actions
  end

  show do
    attributes_table do
      row :id
      row :user
      row :plan
      row :signed_at
      row :created_at

      # 🔹 PDF LINK
      row "Agreement PDF" do |agreement|
        if agreement.pdf.attached?
          link_to "Download PDF",
                  rails_blob_path(agreement.pdf, disposition: "attachment"),
                  target: "_blank"
        else
          status_tag "No PDF", class: "warning"
        end
      end

      # 🔹 SIGNATURE (PREVIEW)
      row "Signature" do |agreement|
        if agreement.signature.attached?
          image_tag url_for(agreement.signature),
                    width: 200,
                    style: "border: 1px solid #ddd; padding: 5px;"
        else
          status_tag "No Signature", class: "warning"
        end
      end
    end
  end
end
