class AddLockoutReasonToUser < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :lockout_reason, :string
  end
end
