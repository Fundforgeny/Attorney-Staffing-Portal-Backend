ActiveAdmin.register Plan do
  permit_params :name,:duration,:total_payment,:total_interest_amount,:monthly_payment,:monthly_interest_amount,:down_payment,:status,:user_id
  
  controller do
    def scoped_collection
      return super unless action_name == "index"

      super.where(status: Plan.statuses[:paid])
    end
  end

  filter :name
  filter :user
  filter :duration
  filter :total_payment
  filter :monthly_payment
  filter :status, as: :select, collection: Plan.statuses.keys.map { |status| [status.to_s.humanize, status] }
  filter :created_at

  action_item :sync_with_ghl, only: :show do
    link_to(
      "Sync with GHL",
      sync_with_ghl_admin_plan_path(resource, inline: "1"),
      method: :post,
      data: { confirm: "Sync this plan with GHL now?" }
    )
  end

  action_item :manual_charge, only: :show do
    next unless resource.user&.payment_methods&.ordered_for_user&.first&.vault_token.present?

    link_to("Charge Saved Card", "#manual-vault-charge")
  end

  member_action :sync_with_ghl, method: :post do
    plan = Plan.find(params[:id])

    response = GhlPlanSyncWorker.new.perform(plan.id)

    if response == :missing_webhook_url
      redirect_to resource_path(plan), alert: "GHL sync failed: webhook URL is not configured."
    elsif response.code.to_i == 200
      redirect_to resource_path(plan), notice: "Successfully synced with GHL."
    else
      error_message = begin
                        JSON.parse(response.body)["message"]
                      rescue
                        response.body.to_s
                      end
      redirect_to resource_path(plan), alert: "GHL sync failed: #{error_message}"
    end
  end

  member_action :manual_charge, method: :post do
    plan = Plan.find(params[:id])

    Admin::ManualVaultChargeService.new(
      plan: plan,
      amount: params[:amount],
      description: params[:description]
    ).call

    redirect_to resource_path(plan), notice: "Manual charge submitted successfully."
  rescue StandardError => e
    redirect_to resource_path(plan), alert: "Manual charge failed: #{e.message}"
  end

  index do
    selectable_column
    id_column
    column :name
    column :user
    column :duration
    column :total_payment
    column :monthly_payment
    column :status
    column("Next Payment Date") { |plan| plan.next_payment_at }
    column :created_at
    actions
  end

  show do
    plan = resource
    user = plan.user
    payments = plan.payments.includes(:payment_method).order(created_at: :desc)
    agreement = plan.agreement
    primary_firm = user&.firm
    associated_firms = user ? user.firms : Firm.none

    panel "Plan Details" do
      div class: "aa-plan-accordion" do
        details open: true, class: "aa-accordion-item" do
          summary "Plan Summary"
          div class: "aa-accordion-body" do
            attributes_table_for plan do
              row :id
              row :name
              row :duration
              row("Base Legal Fee") { |record| number_to_currency(record.base_legal_fee_amount) }
              row("Fund Forge Payment Plan Administration Fee (4%)") { |record| number_to_currency(record.administration_fee_amount) }
              row("Total Payment Plan Amount") { |record| number_to_currency(record.total_payment_plan_amount) }
              row :monthly_payment
              row("Monthly Administration Fee Portion") { |record| number_to_currency(record.monthly_interest_amount || 0) }
              row :down_payment
              row :status do |record|
                status_tag record.status
              end
              row("Next Payment Date") { |record| record.next_payment_at }
              row :created_at
              row :updated_at
            end
          end
        end

        details class: "aa-accordion-item" do
          summary "User Information"
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
                  firm_names = associated_firms.pluck(:name)
                  firm_names.any? ? firm_names.join(", ") : "N/A"
                end
              end
            else
              para "No user found for this plan."
            end
          end
        end

        details class: "aa-accordion-item" do
          summary "Card Details"
          div class: "aa-accordion-body" do
            if user&.payment_method.present?
              attributes_table_for user.payment_method do
                row :provider
                row :card_brand
                row :last4
                row :exp_month
                row :exp_year
                row :cardholder_name
                row :created_at
              end
            else
              para "No card details found."
            end
          end
        end

        details class: "aa-accordion-item" do
          summary "Payments"
          div class: "aa-accordion-body" do
            if payments.any?
              table_for payments do
                column :id
                column :payment_type
                column :payment_amount
                column("Administration Fee") { |payment| number_to_currency(payment.transaction_fee || 0) }
                column("Total Charged") { |payment| number_to_currency(payment.total_payment_including_fee || 0) }
                column :status do |payment|
                  status_tag payment.status
                end
                column("Card") do |payment|
                  payment_method = payment.payment_method
                  if payment_method.present?
                    "#{payment_method.card_brand} ****#{payment_method.last4} (#{payment_method.exp_month}/#{payment_method.exp_year})"
                  else
                    "N/A"
                  end
                end
                column :scheduled_at
                column :paid_at
                column :created_at
              end
            else
              para "No payments found for this plan."
            end
          end
        end

        details class: "aa-accordion-item", id: "manual-vault-charge" do
          summary "Manual Vault Charge"
          div class: "aa-accordion-body" do
            saved_payment_method = user&.payment_methods&.ordered_for_user&.first

            if saved_payment_method&.vault_token.present?
              para "Charge a specific amount to the saved vaulted card on file."
              para "Saved card: #{saved_payment_method.card_brand} ****#{saved_payment_method.last4} (#{saved_payment_method.exp_month}/#{saved_payment_method.exp_year})"

              div do
                form action: manual_charge_admin_plan_path(plan), method: :post do
                  input type: :hidden, name: :authenticity_token, value: form_authenticity_token
                  div do
                    label "Amount (USD)", for: "manual_charge_amount"
                    input id: "manual_charge_amount", type: :number, name: :amount, step: "0.01", min: "0.01", required: true
                  end
                  div style: "margin-top: 12px;" do
                    label "Description", for: "manual_charge_description"
                    input id: "manual_charge_description", type: :text, name: :description, value: "Admin manual payment"
                  end
                  div style: "margin-top: 12px;" do
                    input type: :submit, value: "Charge Saved Card"
                  end
                end
              end
            else
              para "No saved vaulted payment method found for this user."
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
                  if agreement.engagement_pdf.attached?
                    link_to "View Engagement Letter", url_for(agreement.engagement_pdf), target: "_blank", rel: "noopener"
                  else
                    "Not available"
                  end
                end
                row("Financing Contract") do
                  if agreement.pdf.attached?
                    link_to "View Financing Contract", url_for(agreement.pdf), target: "_blank", rel: "noopener"
                  else
                    "Not available"
                  end
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
      f.input :status, as: :select, collection: Plan.statuses.keys.map { |status| [status.to_s.humanize, status] }
    end
    f.actions
  end
end
