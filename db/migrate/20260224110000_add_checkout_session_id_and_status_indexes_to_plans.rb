class AddCheckoutSessionIdAndStatusIndexesToPlans < ActiveRecord::Migration[8.0]
  def up
    add_column :plans, :checkout_session_id, :string unless column_exists?(:plans, :checkout_session_id)

    # Preserve legacy semantic meaning when migrating old enum values:
    # active(0) -> draft(0), completed(1) -> paid(3), cancelled(2) -> failed(4)
    execute <<~SQL
      UPDATE plans
      SET status = CASE status
                   WHEN 1 THEN 3
                   WHEN 2 THEN 4
                   ELSE status
                   END
    SQL

    Plan.reset_column_information
    Plan.where(checkout_session_id: [ nil, "" ]).find_each do |plan|
      plan.update_columns(checkout_session_id: "legacy-plan-#{plan.id}")
    end

    change_column_default :plans, :status, from: 0, to: 0
    change_column_null :plans, :status, false
    change_column_null :plans, :checkout_session_id, false

    add_index :plans, :checkout_session_id, unique: true unless index_exists?(:plans, :checkout_session_id, unique: true)
    add_index :plans, :status unless index_exists?(:plans, :status)
  end

  def down
    remove_index :plans, :status if index_exists?(:plans, :status)
    remove_index :plans, :checkout_session_id if index_exists?(:plans, :checkout_session_id)
    remove_column :plans, :checkout_session_id if column_exists?(:plans, :checkout_session_id)

    # Roll back migrated status values
    execute <<~SQL
      UPDATE plans
      SET status = CASE status
                   WHEN 3 THEN 1
                   WHEN 4 THEN 2
                   ELSE status
                   END
    SQL
  end
end

