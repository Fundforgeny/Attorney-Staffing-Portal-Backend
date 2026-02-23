ActiveAdmin.register_page "Leads" do
  menu priority: 4, label: "Leads"

  content title: "Leads" do
    leads = User.joins(:plans)
                .where("plans.magic_link_token IS NOT NULL AND plans.magic_link_token != ''")
                .where.not(id: Payment.succeeded.select(:user_id))
                .includes(:plans, :firm)
                .distinct
                .order("users.id DESC")
    paginated_leads = leads.page(params[:page]).per(20)

    panel "Unpaid Magic-Link Leads" do
      if paginated_leads.any?
        paginated_collection(paginated_leads, download_links: false) do
          table_for collection do
            column :id
            column :email
            column :first_name
            column :last_name
            column :phone
            column("Firm") { |lead| lead.firm&.name || "N/A" }
            column("Latest Plan") { |lead| lead.plans.max_by(&:created_at)&.name || "N/A" }
            column("Actions") do |lead|
              link_to("View User", admin_user_path(lead))
            end
          end
        end
      else
        para "No leads found."
      end
    end
  end
end

