class AddMagicLinkTokenToPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :plans, :magic_link_token, :string
  end
end
