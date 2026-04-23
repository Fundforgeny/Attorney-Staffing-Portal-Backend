class AddChargeflowFieldsToPaymentsAndPlans < ActiveRecord::Migration[8.0]
  def change
    # ── Payments ──────────────────────────────────────────────────────────────
    # Track whether this payment has been disputed via Chargeflow
    add_column :payments, :disputed,               :boolean, default: false, null: false
    # Chargeflow alert ID (from alerts.created webhook)
    add_column :payments, :chargeflow_alert_id,    :string
    # Chargeflow dispute ID (from dispute.created webhook)
    add_column :payments, :chargeflow_dispute_id,  :string
    # Timestamp when the dispute was received
    add_column :payments, :disputed_at,            :datetime
    # Flag to identify this payment as a Chargeflow dispute recovery charge
    # (disputed amount + $100 fee, retried via normal payday schedule)
    add_column :payments, :chargeflow_recovery,    :boolean, default: false, null: false

    add_index :payments, :disputed
    add_index :payments, :chargeflow_alert_id
    add_index :payments, :chargeflow_dispute_id
    add_index :payments, :chargeflow_recovery

    # ── Plans ─────────────────────────────────────────────────────────────────
    # Cumulative $100 Chargeflow alert/dispute fees applied to this plan
    add_column :plans, :chargeflow_alert_fee, :decimal, precision: 10, scale: 2, default: 0, null: false
  end
end
