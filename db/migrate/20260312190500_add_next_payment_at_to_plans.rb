class AddNextPaymentAtToPlans < ActiveRecord::Migration[8.0]
  def up
    add_column :plans, :next_payment_at, :datetime unless column_exists?(:plans, :next_payment_at)

    execute <<~SQL
      UPDATE plans
      SET next_payment_at = next_payments.scheduled_at
      FROM (
        SELECT DISTINCT ON (plan_id)
               plan_id,
               scheduled_at
        FROM payments
        WHERE payment_type = 1
          AND status IN (0, 1)
          AND scheduled_at IS NOT NULL
        ORDER BY plan_id, scheduled_at ASC
      ) AS next_payments
      WHERE plans.id = next_payments.plan_id
    SQL
  end

  def down
    remove_column :plans, :next_payment_at if column_exists?(:plans, :next_payment_at)
  end
end
