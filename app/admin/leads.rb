ActiveAdmin.register_page "Leads" do
  menu priority: 4, label: "Leads"

  content title: "Leads" do
    leads = Plan.includes(:user)
                .where.not(status: Plan.statuses[:paid])
                .order(created_at: :desc)
    paginated_leads = leads.page(params[:page]).per(20)

    panel "Leads (All Non-Paid Plans)" do
      if paginated_leads.any?
        paginated_collection(paginated_leads, download_links: false) do
          table_for collection do
            column :id
            column("Plan") { |plan| plan.name }
            column("Status") { |plan| status_tag(plan.status) }
            column("User Email") { |plan| plan.user&.email || "N/A" }
            column("User Name") { |plan| plan.user&.full_name || "N/A" }
            column("Total Payment") { |plan| number_to_currency(plan.total_payment || 0) }
            column("Created At", &:created_at)
            column("Actions") do |plan|
              link_to("View Plan", admin_plan_path(plan))
            end
          end
        end
      else
        para "No leads found."
      end
    end
  end
end

