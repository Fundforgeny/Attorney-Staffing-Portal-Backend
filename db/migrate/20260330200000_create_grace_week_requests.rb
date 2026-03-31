class CreateGraceWeekRequests < ActiveRecord::Migration[7.2]
  def change
    create_table :grace_week_requests do |t|
      t.references :plan,    null: false, foreign_key: true
      t.references :user,    null: false, foreign_key: true
      t.references :payment, null: false, foreign_key: true  # the original installment being split

      t.integer :status,          null: false, default: 0  # 0=pending, 1=approved, 2=denied
      t.text    :reason                                              # client's reason for requesting
      t.text    :admin_note                                         # admin note on approval/denial
      t.decimal :half_amount,     precision: 10, scale: 2          # installment / 2
      t.date    :first_half_due                                     # original due + 7 days
      t.date    :second_half_due                                    # original due + 14 days
      t.integer :halves_paid,     default: 0                        # 0, 1, or 2
      t.datetime :approved_at
      t.datetime :denied_at
      t.datetime :requested_at,   null: false

      t.timestamps
    end

    add_index :grace_week_requests, :status
    add_index :grace_week_requests, [:plan_id, :status]

    # Track grace week on the payment itself
    add_column :payments, :grace_week_request_id, :bigint
    add_index  :payments, :grace_week_request_id
  end
end
