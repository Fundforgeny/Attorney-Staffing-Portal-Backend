ActiveAdmin.register GraceWeekRequest do
  menu priority: 4, label: "Grace Week Queue"

  permit_params :status, :admin_note

  # ── Scopes ────────────────────────────────────────────────────────────────
  scope("Pending Review", default: true) { |s| s.where(status: :pending) }
  scope :approved
  scope :denied
  scope :all

  # ── Filters ───────────────────────────────────────────────────────────────
  filter :plan
  filter :user
  filter :status, as: :select, collection: GraceWeekRequest.statuses.keys.map { |s| [s.humanize, s] }
  filter :requested_at
  filter :created_at

  # ── Index ─────────────────────────────────────────────────────────────────
  index do
    selectable_column
    id_column
    column :plan
    column :user
    column("Half Amount") { |g| number_to_currency(g.half_amount) }
    column :status do |g|
      status_tag g.status
    end
    column("Reason")       { |g| g.reason.to_s.truncate(50) }
    column("Halves Paid")  { |g| "#{g.halves_paid}/2" }
    column("First Half Due")  { |g| g.first_half_due || "—" }
    column("Second Half Due") { |g| g.second_half_due || "—" }
    column :requested_at
    actions
  end

  # ── Show ──────────────────────────────────────────────────────────────────
  show do
    grace = resource

    attributes_table do
      row :id
      row :plan
      row :user
      row :payment
      row :status do
        status_tag grace.status
      end
      row("Half Amount")      { number_to_currency(grace.half_amount) }
      row("Halves Paid")      { "#{grace.halves_paid}/2" }
      row("First Half Due")   { grace.first_half_due || "—" }
      row("Second Half Due")  { grace.second_half_due || "—" }
      row("Client Reason")    { grace.reason.presence || "No reason provided" }
      row("Admin Note")       { grace.admin_note.presence || "—" }
      row :requested_at
      row :approved_at
      row :denied_at
      row :created_at
    end

    if grace.pending?
      panel "Take Action" do
        div style: "display:flex;gap:16px;flex-wrap:wrap;" do
          concat(
            form_tag(approve_grace_week_admin_plan_path(grace.plan, grace_week_request_id: grace.id), method: :post) do
              concat hidden_field_tag(:authenticity_token, form_authenticity_token)
              concat text_field_tag(:admin_note, "", placeholder: "Admin note (optional)", style: "padding:6px;width:250px;margin-right:8px;")
              concat submit_tag("✓ Approve Grace Week",
                                style: "background:#27ae60;color:#fff;padding:8px 16px;border:none;border-radius:4px;cursor:pointer;font-size:14px;",
                                data: { confirm: "Approve grace week — split #{number_to_currency(grace.half_amount)} × 2?" })
            end
          )
          concat(
            form_tag(deny_grace_week_admin_plan_path(grace.plan, grace_week_request_id: grace.id), method: :post) do
              concat hidden_field_tag(:authenticity_token, form_authenticity_token)
              concat text_field_tag(:admin_note, "", placeholder: "Reason for denial", style: "padding:6px;width:220px;margin-right:8px;")
              concat submit_tag("✗ Deny",
                                style: "background:#e74c3c;color:#fff;padding:8px 16px;border:none;border-radius:4px;cursor:pointer;font-size:14px;",
                                data: { confirm: "Deny this grace week request?" })
            end
          )
        end
      end
    end
  end
end
