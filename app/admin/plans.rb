ActiveAdmin.register Plan do
  permit_params :name, :duration, :total_payment, :total_interest_amount,
                :monthly_payment, :monthly_interest_amount, :down_payment,
                :status, :user_id

  # ── Scopes ────────────────────────────────────────────────────────────────
  scope :all, default: true
  scope("Draft")           { |q| q.where(status: :draft) }
  scope("Payment Pending") { |q| q.where(status: :payment_pending) }
  scope("Paid")            { |q| q.where(status: :paid) }
  scope("Failed")          { |q| q.where(status: :failed) }
  scope("Agreement Generated") { |q| q.where(status: :agreement_generated) }

  # ── Filters ───────────────────────────────────────────────────────────────
  filter :name
  filter :user
  filter :user_email_cont, as: :string, label: "User Email"
  filter :duration
  filter :total_payment
  filter :monthly_payment
  filter :status, as: :select, collection: Plan.statuses.keys.map { |s| [s.humanize, s] }
  filter :created_at

  # ── Action Items (top bar on show page) ───────────────────────────────────
  action_item :sync_with_ghl, only: :show do
    link_to "Sync with GHL",
            sync_with_ghl_admin_plan_path(resource, inline: "1"),
            method: :post,
            data: { confirm: "Sync this plan with GHL now?" }
  end

  action_item :manual_charge, only: :show do
    next unless resource.user&.payment_methods&.ordered_for_user&.first&.vault_token.present?
    link_to "Charge Saved Card", "#manual-vault-charge"
  end

  action_item :add_card, only: :show do
    next unless resource.user.present?
    link_to "Add Card for Client", "#add-card-section"
  end

  # ── Member Actions ────────────────────────────────────────────────────────

  member_action :sync_with_ghl, method: :post do
    plan = Plan.find(params[:id])
    response = GhlPlanSyncWorker.new.perform(plan.id)
    if response == :missing_webhook_url
      redirect_to resource_path(plan), alert: "GHL sync failed: webhook URL is not configured."
    elsif response.code.to_i == 200
      redirect_to resource_path(plan), notice: "Successfully synced with GHL."
    else
      error_message = begin; JSON.parse(response.body)["message"]; rescue; response.body.to_s; end
      redirect_to resource_path(plan), alert: "GHL sync failed: #{error_message}"
    end
  end

  # Manual charge against a specific active payment method only.
  member_action :manual_charge, method: :post do
    plan = Plan.find(params[:id])
    pm   = params[:payment_method_id].present? ?
             plan.user.payment_methods.active.find(params[:payment_method_id]) :
             plan.user.payment_methods.ordered_for_user.first

    raise "No active payment method on file" unless pm

    Admin::ManualVaultChargeService.new(
      plan:           plan,
      amount:         params[:amount],
      description:    params[:description].presence || "Admin manual payment",
      payment_method: pm
    ).call

    redirect_to resource_path(plan), notice: "Manual charge of $#{params[:amount]} submitted successfully."
  rescue StandardError => e
    redirect_to resource_path(plan), alert: "Manual charge failed: #{e.message}"
  end

  # Charge a specific pending/failed payment row right now
  member_action :charge_now, method: :post do
    plan    = Plan.find(params[:id])
    payment = plan.payments.find(params[:payment_id])

    ChargePaymentWorker.perform_async(payment.id)
    redirect_to resource_path(plan), notice: "Charge job queued for payment ##{payment.id}."
  rescue ActiveRecord::RecordNotFound
    redirect_to resource_path(plan), alert: "Payment not found."
  end

  # Set a card as the client's default. This is express reactivation/permission
  # if the card had previously been archived.
  member_action :set_default_card, method: :post do
    plan = Plan.find(params[:id])
    pm   = plan.user.payment_methods.find(params[:payment_method_id])
    plan.user.payment_methods.active.update_all(is_default: false)
    pm.update!(is_default: true, archived_at: nil)
    redirect_to resource_path(plan), notice: "#{pm.card_brand&.upcase} ••••#{pm.last4} set as default card."
  rescue ActiveRecord::RecordNotFound
    redirect_to resource_path(plan), alert: "Card not found."
  end

  # Remove a card from active use without redacting it from Spreedly.
  member_action :delete_card, method: :delete do
    plan = Plan.find(params[:id])
    pm   = plan.user.payment_methods.find(params[:payment_method_id])

    deleted_default = pm.is_default?
    pm.archive!

    if deleted_default
      plan.user.payment_methods.active.order(created_at: :desc).first&.update!(is_default: true)
    end

    redirect_to resource_path(plan), notice: "Card removed from active use. Vault token preserved and will not be used without express reactivation/permission."
  rescue ActiveRecord::RecordNotFound
    redirect_to resource_path(plan), alert: "Card not found."
  end

  # Approve a grace week request
  member_action :approve_grace_week, method: :post do
    plan  = Plan.find(params[:id])
    grace = plan.grace_week_requests.find(params[:grace_week_request_id])
    GraceWeekService.approve!(grace: grace, admin_note: params[:admin_note])
    redirect_to resource_path(plan), notice: "Grace week approved. Two half-payments scheduled."
  rescue GraceWeekService::Error => e
    redirect_to resource_path(plan), alert: "Grace week approval failed: #{e.message}"
  end

  # Deny a grace week request
  member_action :deny_grace_week, method: :post do
    plan  = Plan.find(params[:id])
    grace = plan.grace_week_requests.find(params[:grace_week_request_id])
    GraceWeekService.deny!(grace: grace, admin_note: params[:admin_note])
    redirect_to resource_path(plan), notice: "Grace week denied. Retries resumed."
  rescue GraceWeekService::Error => e
    redirect_to resource_path(plan), alert: "Grace week denial failed: #{e.message}"
  end

  # ── Index ─────────────────────────────────────────────────────────────────
  index do
    selectable_column
    id_column
    column :name
    column :user
    column :duration
    column("Total")   { |p| number_to_currency(p.total_payment) }
    column("Monthly") { |p| number_to_currency(p.monthly_payment) }
    column :status do |p|
      status_tag p.status
    end
    column("Next Payment") { |p| p.next_payment_at&.strftime("%b %-d, %Y") || "—" }
    column("Needs Card") do |p|
      p.payments.where(needs_new_card: true).exists? ? status_tag("Yes", class: "status_tag error") : "—"
    end
    column :created_at
    actions
  end

  # ── Show ──────────────────────────────────────────────────────────────────
  show do
    plan             = resource
    user             = plan.user
    payments         = plan.payments.includes(:payment_method).order(scheduled_at: :asc, created_at: :asc)
    agreement        = plan.agreement
    primary_firm     = user&.firm
    associated_firms = user ? user.firms : Firm.none
    all_cards        = user&.payment_methods&.ordered_for_user || []
    grace_requests   = plan.grace_week_requests.recent

    panel "Plan Details" do
      div class: "aa-plan-accordion" do

        details open: true, class: "aa-accordion-item" do
          summary "Plan Summary"
          div class: "aa-accordion-body" do
            attributes_table_for plan do
              row :id
              row :name
              row :duration
              row("Base Legal Fee")                           { number_to_currency(plan.base_legal_fee_amount) }
              row("Fund Forge Administration Fee (4%)")       { number_to_currency(plan.administration_fee_amount) }
              row("Total Payment Plan Amount")                { number_to_currency(plan.total_payment_plan_amount) }
              row("Monthly Payment")                          { number_to_currency(plan.monthly_payment) }
              row("Monthly Administration Fee Portion")       { number_to_currency(plan.monthly_interest_amount || 0) }
              row("Down Payment")                             { number_to_currency(plan.down_payment) }
              row("Remaining Balance")                        { number_to_currency(plan.remaining_balance_logic) }
              row :status do
                status_tag plan.status
              end
              row("Next Payment Date") { plan.next_payment_at&.strftime("%B %-d, %Y") || "—" }
              row :created_at
              row :updated_at
            end
          end
        end

        details class: "aa-accordion-item" do
          summary "Client Information"
          div class: "aa-accordion-body" do
            if user.present?
              attributes_table_for user do
                row :id
                row :email
                row :first_name
                row :last_name
                row :phone
                row :user_type
                row :city
                row :state
                row :country
                row("Primary Firm") { primary_firm&.name || "N/A" }
                row("All Firms") do
                  names = associated_firms.pluck(:name)
                  names.any? ? names.join(", ") : "N/A"
                end
              end
            else
              para "No user found for this plan."
            end
          end
        end

        details open: true, class: "aa-accordion-item", id: "card-management-section" do
          summary "Card Management"
          div class: "aa-accordion-body" do
            if all_cards.any?
              table_for all_cards do
                column("Brand")   { |c| c.card_brand&.upcase || "CARD" }
                column("Last 4")  { |c| "••••#{c.last4}" }
                column("Expires") { |c| "#{c.exp_month}/#{c.exp_year}" }
                column("Name")    { |c| c.cardholder_name }
                column("Default") do |c|
                  c.is_default? ? status_tag("Default", class: "status_tag ok") : "—"
                end
                column("Vault Token") { |c| c.vault_token.present? ? "✓ Vaulted" : span("Missing", style: "color:#e74c3c;") }
                column("Actions") do |c|
                  div style: "display:flex;gap:6px;flex-wrap:wrap;" do
                    unless c.is_default?
                      concat link_to("Set Default",
                        set_default_card_admin_plan_path(plan, payment_method_id: c.id),
                        method: :post,
                        data: { confirm: "Set #{c.card_brand&.upcase} ••••#{c.last4} as default? Only do this with express permission to use this card." },
                        class: "button")
                    end
                    concat link_to("Remove",
                      delete_card_admin_plan_path(plan, payment_method_id: c.id),
                      method: :delete,
                      data: { confirm: "Remove #{c.card_brand&.upcase} ••••#{c.last4} from active use? The vault token will be preserved and not redacted." },
                      class: "button",
                      style: "background:#e74c3c;color:#fff;")
                  end
                end
              end
            else
              para "No saved cards on file for this client."
            end

            if all_cards.any?
              h4 "Manual Charge", style: "margin-top:20px;"
              para "Only active cards appear here. Archived cards may not be used without express reactivation/permission.", style: "color:#667085;font-size:12px;"
              div id: "manual-vault-charge" do
                form action: manual_charge_admin_plan_path(plan), method: :post do
                  input type: :hidden, name: :authenticity_token, value: form_authenticity_token
                  div style: "display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px;margin-bottom:12px;" do
                    div do
                      label "Card", for: "charge_pm_id"
                      select name: :payment_method_id, id: "charge_pm_id", style: "width:100%;padding:6px;" do
                        all_cards.each do |c|
                          option "#{c.card_brand&.upcase} ••••#{c.last4} (#{c.exp_month}/#{c.exp_year})#{c.is_default? ? ' ★' : ''}",
                                 value: c.id
                        end
                      end
                    end
                    div do
                      label "Amount (USD)", for: "manual_charge_amount"
                      input id: "manual_charge_amount", type: :number, name: :amount,
                            step: "0.01", min: "0.01",
                            value: plan.monthly_payment,
                            required: true,
                            style: "width:100%;padding:6px;"
                    end
                    div do
                      label "Description", for: "manual_charge_desc"
                      input id: "manual_charge_desc", type: :text, name: :description,
                            value: "Admin manual payment",
                            style: "width:100%;padding:6px;"
                    end
                  end
                  input type: :submit, value: "Charge Card Now",
                        style: "background:#1132d4;color:#fff;padding:8px 18px;border:none;border-radius:4px;cursor:pointer;"
                end
              end
            end

            h4 "Add New Card for Client", style: "margin-top:24px;", id: "add-card-section"
            para "Use the Spreedly Express checkout or paste a vault token to add a new card to this client's profile.", style: "color:#667085;font-size:13px;"
            div do
              form action: add_card_admin_plan_path(plan), method: :post, id: "add-card-form" do
                input type: :hidden, name: :authenticity_token, value: form_authenticity_token
                div style: "display:grid;grid-template-columns:1fr 1fr 1fr 1fr;gap:10px;margin-bottom:12px;" do
                  div do
                    label "Vault Token", for: "new_vault_token"
                    input id: "new_vault_token", type: :text, name: :vault_token,
                          placeholder: "Spreedly vault token",
                          style: "width:100%;padding:6px;"
                  end
                  div do
                    label "Card Brand", for: "new_card_brand"
                    input id: "new_card_brand", type: :text, name: :card_brand,
                          placeholder: "Visa / Mastercard",
                          style: "width:100%;padding:6px;"
                  end
                  div do
                    label "Last 4", for: "new_last4"
                    input id: "new_last4", type: :text, name: :last4,
                          maxlength: 4, placeholder: "1234",
                          style: "width:100%;padding:6px;"
                  end
                  div do
                    label "Exp (MM/YYYY)", for: "new_exp"
                    input id: "new_exp", type: :text, name: :expiry,
                          placeholder: "12/2028",
                          style: "width:100%;padding:6px;"
                  end
                end
                div do
                  label "Cardholder Name", for: "new_cardholder"
                  input id: "new_cardholder", type: :text, name: :cardholder_name,
                        value: user&.full_name,
                        style: "width:300px;padding:6px;"
                end
                div style: "margin-top:10px;" do
                  input type: :submit, value: "Save Card",
                        style: "background:#28a745;color:#fff;padding:8px 18px;border:none;border-radius:4px;cursor:pointer;"
                end
              end
            end
          end
        end

        details open: true, class: "aa-accordion-item" do
          summary "Payments & Retry Status"
          div class: "aa-accordion-body" do
            if payments.any?
              table_for payments do
                column :id
                column("Type")    { |p| p.payment_type.humanize }
                column("Amount")  { |p| number_to_currency(p.payment_amount) }
                column("Fee")     { |p| number_to_currency(p.transaction_fee || 0) }
                column("Total")   { |p| number_to_currency(p.total_payment_including_fee || 0) }
                column :status do |p|
                  status_tag p.status
                end
                column("Retries") do |p|
                  p.retry_count.to_i > 0 ?
                    span("#{p.retry_count} attempt#{p.retry_count == 1 ? '' : 's'}",
                         style: "background:#f39c12;color:#fff;padding:2px 8px;border-radius:10px;font-size:11px;") :
                    "—"
                end
                column("Needs Card") do |p|
                  p.needs_new_card? ?
                    span("NEEDS CARD", style: "background:#e74c3c;color:#fff;padding:2px 8px;border-radius:10px;font-size:11px;") :
                    "—"
                end
                column("Decline Reason") do |p|
                  r = p.decline_reason
                  (r.present? && !r.start_with?("covered_by") && r != "grace_week_approved") ?
                    span(r.truncate(38), style: "color:#c0392b;font-size:11px;") : "—"
                end
                column("Card") do |p|
                  pm = p.payment_method
                  pm.present? ? "#{pm.card_brand&.upcase} ••••#{pm.last4}" : "—"
                end
                column("Scheduled")  { |p| p.scheduled_at&.strftime("%b %-d, %Y") || "—" }
                column("Paid")       { |p| p.paid_at&.strftime("%b %-d, %Y") || "—" }
                column("Next Retry") { |p| p.next_retry_at&.strftime("%b %-d, %Y") || "—" }
                column("Actions") do |p|
                  if (p.pending? || p.processing? || p.failed?) && !p.needs_new_card?
                    link_to "Charge Now",
                            charge_now_admin_plan_path(plan, payment_id: p.id),
                            method: :post,
                            data: { confirm: "Charge #{number_to_currency(p.total_payment_including_fee)} now?" },
                            class: "button",
                            style: "font-size:11px;padding:3px 10px;background:#1132d4;color:#fff;"
                  end
                end
              end
            else
              para "No payments found for this plan."
            end
          end
        end

        if grace_requests.any?
          details open: grace_requests.where(status: :pending).any?, class: "aa-accordion-item" do
            summary "Grace Week Requests #{grace_requests.where(status: :pending).any? ? '⚠ Pending Review' : ''}"
            div class: "aa-accordion-body" do
              grace_requests.each do |gr|
                div style: "border:1px solid #e0e0e0;border-radius:8px;padding:16px;margin-bottom:12px;" do
                  div style: "display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;" do
                    span "Request ##{gr.id} — #{gr.status.upcase}",
                         style: "font-weight:600;font-size:14px;"
                    status_tag gr.status
                  end
                  para "Requested: #{gr.requested_at&.strftime('%B %-d, %Y at %-I:%M %p')}", style: "font-size:12px;color:#667085;"
                  para "Client reason: #{gr.reason.presence || 'No reason provided'}", style: "font-size:13px;"
                  if gr.half_amount.present?
                    para "Half-payment amount: #{number_to_currency(gr.half_amount)}", style: "font-size:13px;"
                  end
                  if gr.approved?
                    para "First half due: #{gr.first_half_due&.strftime('%B %-d, %Y')}", style: "font-size:13px;color:#27ae60;"
                    para "Second half due: #{gr.second_half_due&.strftime('%B %-d, %Y')}", style: "font-size:13px;color:#27ae60;"
                    para "Halves paid: #{gr.halves_paid}/2", style: "font-size:13px;"
                  end
                  if gr.admin_note.present?
                    para "Admin note: #{gr.admin_note}", style: "font-size:12px;color:#667085;font-style:italic;"
                  end

                  if gr.pending?
                    div style: "display:flex;gap:10px;margin-top:12px;" do
                      concat(
                        form_tag(approve_grace_week_admin_plan_path(plan, grace_week_request_id: gr.id), method: :post, style: "display:inline;") do
                          concat hidden_field_tag(:authenticity_token, form_authenticity_token)
                          concat text_field_tag(:admin_note, "", placeholder: "Admin note (optional)", style: "padding:5px;width:220px;margin-right:6px;")
                          concat submit_tag("Approve Grace Week",
                                            style: "background:#27ae60;color:#fff;padding:7px 14px;border:none;border-radius:4px;cursor:pointer;",
                                            data: { confirm: "Approve grace week for #{number_to_currency(gr.half_amount)} × 2?" })
                        end
                      )
                      concat(
                        form_tag(deny_grace_week_admin_plan_path(plan, grace_week_request_id: gr.id), method: :post, style: "display:inline;") do
                          concat hidden_field_tag(:authenticity_token, form_authenticity_token)
                          concat text_field_tag(:admin_note, "", placeholder: "Reason for denial", style: "padding:5px;width:200px;margin-right:6px;")
                          concat submit_tag("Deny",
                                            style: "background:#e74c3c;color:#fff;padding:7px 14px;border:none;border-radius:4px;cursor:pointer;",
                                            data: { confirm: "Deny this grace week request?" })
                        end
                      )
                    end
                  end
                end
              end
            end
          end
        end

        details class: "aa-accordion-item" do
          summary "Contract Documents"
          div class: "aa-accordion-body" do
            if agreement.present?
              attributes_table_for agreement do
                row :id
                row :signed_at
                row :created_at
                row("Engagement Letter") do
                  agreement.engagement_pdf.attached? ?
                    link_to("View Engagement Letter", url_for(agreement.engagement_pdf), target: "_blank", rel: "noopener") :
                    "Not available"
                end
                row("Financing Contract") do
                  agreement.pdf.attached? ?
                    link_to("View Financing Contract", url_for(agreement.pdf), target: "_blank", rel: "noopener") :
                    "Not available"
                end
              end
            else
              para "No agreement found for this plan."
            end
          end
        end
      end
    end
  end

  # ── Add Card member action ────────────────────────────────────────────────
  member_action :add_card, method: :post do
    plan = Plan.find(params[:id])
    user = plan.user

    vault_token = params[:vault_token].to_s.strip
    return redirect_to(resource_path(plan), alert: "Vault token is required.") if vault_token.blank?

    expiry_parts = params[:expiry].to_s.split("/")
    exp_month    = expiry_parts[0].to_i
    exp_year     = expiry_parts[1].to_i

    pm = user.payment_methods.find_or_initialize_by(vault_token: vault_token)
    pm.assign_attributes(
      provider:        "Spreedly Vault",
      card_brand:      params[:card_brand].presence || "Card",
      last4:           params[:last4].presence,
      exp_month:       exp_month.positive? ? exp_month : nil,
      exp_year:        exp_year.positive? ? exp_year : nil,
      cardholder_name: params[:cardholder_name].presence || user.full_name,
      archived_at:     nil,
      is_default:      user.payment_methods.active.blank?
    )
    pm.save!

    redirect_to resource_path(plan), notice: "Card ••••#{pm.last4} added/reactivated successfully."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to resource_path(plan), alert: "Failed to add card: #{e.message}"
  end

  form do |f|
    f.semantic_errors
    f.inputs "Plan Details" do
      f.input :user
      f.input :name
      f.input :duration
      f.input :total_payment, min: 0.01
      f.input :total_interest_amount, min: 0
      f.input :monthly_payment, min: 0
      f.input :monthly_interest_amount, min: 0
      f.input :down_payment, min: 0
      f.input :status, as: :select,
              collection: Plan.statuses.keys.map { |s| [s.humanize, s] }
    end
    f.actions
  end
end
