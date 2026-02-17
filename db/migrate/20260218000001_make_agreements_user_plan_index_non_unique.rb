class MakeAgreementsUserPlanIndexNonUnique < ActiveRecord::Migration[7.1]
  def up
    remove_index :agreements, name: "index_agreements_on_user_id_and_plan_id"
    add_index :agreements, [:user_id, :plan_id], name: "index_agreements_on_user_id_and_plan_id", unique: false
  end

  def down
    remove_index :agreements, name: "index_agreements_on_user_id_and_plan_id"
    add_index :agreements, [:user_id, :plan_id], name: "index_agreements_on_user_id_and_plan_id", unique: true
  end
end

