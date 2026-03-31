ActiveAdmin.register Payment do
  menu priority: 3, label: "Payments"

  permit_params :user_id, :plan_id, :payment_method_id, :payment_type,
                :payment_amount, :status, :scheduled_at, :paid_at,
                :total_payment_including_fee, :transaction_fee,
                :retry_count, :next_retry_at, :needs_new_card

  # ── Scopes ────────────────────────────────────────────────────────────────
  scope :all
  scope :succeeded, default: true
  scope :pending
  scope :processing
  scope :failed
  scope("Needs New Card") { |s| s.where(needs_new_card: true) }
  scope("Retrying")       { |s| s.where("retry_count > 0").where(status: [Payment.statuses[:pending], Payment.statuses[:processing]]).where(needs_new_card: false) }

  # ── Filters ───────────────────────────────────────────────────────────────
  filter :user
  filter :plan
  filter :payment_type, as: :select, collection: Payment.payment_types.keys.map { |t| [t.humanize, t] }
  filter :status, as: :select, collection: Payment.statuses.keys.map { |s| [s.humanize, s] }
  filter :needs_new_card, as: :boolean
  filter :retry_count
  filter :payment_amount
  filter :scheduled_at
  filter :paid_at
  filter :created_at

  # ── Index ─────────────────────────────────────────────────────────────────
  index do
    selectable_column
    id_column
    column :user
    column :plan
    column :payment_type
    column("Amount") { |p| number_to_currency(p.payment_amount) }
    column("Fee")    { |p| number_to_currency(p.transaction_fee || 0) }
    column("Total")  { |p| number_to_currency(p.total_payment_including_fee || 0) }
    column :status do |p|
      status_tag p.status
    end
    column("Retries") do |p|
      p.retry_count.to_i > 0 ? span(p.retry_count, class: "status_tag warning") : "—"
    end
    column("Needs Card") do |p|
      p.needs_new_card? ? status_tag("Yes", class: "status_tag error") : "—"
    end
    column("Decline Reason") do |p|
      r = p.decline_reason
      (r.present? && !r.start_with?("covered_by")) ? r.truncate(40) : "—"
    end
    column :scheduled_at
    column :paid_at
    column :next_retry_at
    actions
  end

  # ── Show ──────────────────────────────────────────────────────────────────
  show do
    payment = resource
    plan    = payment.plan
    user    = payment.user

    columns do
      column do
        panel "Payment Details" do
          attributes_table_for payment do
            row :id
            row :payment_type
            row("Amount")  { number_to_currency(payment.payment_amount) }
            row("Fee")     { number_to_currency(payment.transaction_fee || 0) }
            row("Total")   { number_to_currency(payment.total_payment_including_fee || 0) }
            row :status do
              status_tag payment.status
            end
            row :charge_id
            row :scheduled_at
            row :paid_at
            row :created_at
            row :updated_at
          end
        end

        panel "Retry & Recovery Status" do
          attributes_table_for payment do
            row("Attempt Count") { payment.retry_count.to_i }
            row("Last Attempt")  { payment.last_attempt_at || "—" }
            row("Next Retry")    { payment.next_retry_at || "—" }
            row("Decline Reason") do
              reason = payment.decline_reason
              if reason.blank? || reason.start_with?("covered_by")
                "—"
              else
                span reason, style: "color: #c0392b; font-weight: 600;"
              end
            end
            row("Needs New Card") do
              payment.needs_new_card? ? status_tag("Yes", class: "status_tag error") : status_tag("No", class: "status_tag ok")
            end
          end
        end
      end

      column do
        panel "Plan" do
          if plan
            attributes_table_for plan do
              row :id
              row :name
              row :status do
                status_tag plan.status
              end
              row("Monthly Payment")   { number_to_currency(plan.monthly_payment) }
              row("Remaining Balance") { number_to_currency(plan.remaining_balance_logic) }
              row :next_payment_at
              row :duration
            end
            div { link_to "View Plan →", admin_plan_path(plan), class: "button" }
          else
            para "No plan associated."
          end
        end

        panel "Client" do
          if user
            attributes_table_for user do
              row :id
              row :email
              row("Name") { user.full_name }
              row :phone
            end
          else
            para "No user associated."
          end
        end
      end
    end
  end

  # ── Form ──────────────────────────────────────────────────────────────────
  form do |f|
    f.inputs "Payment Details" do
      f.input :user
      f.input :plan
      f.input :payment_type
      f.input :payment_amount
      f.input :transaction_fee, label: "Administration Fee"
      f.input :total_payment_including_fee, label: "Total Charged"
      f.input :status
      f.input :scheduled_at, as: :datetime_picker
      f.input :paid_at, as: :datetime_picker
    end
    f.inputs "Retry Status" do
      f.input :retry_count
      f.input :next_retry_at, as: :datetime_picker
      f.input :needs_new_card
    end
    f.actions
  end
end
