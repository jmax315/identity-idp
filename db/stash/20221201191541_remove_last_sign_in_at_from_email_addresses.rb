class RemoveLastSignInAtFromEmailAddresses < ActiveRecord::Migration[7.0]
  def change
    safety_assured { remove_column :email_addresses, :last_sign_in_at, :datetime }
  end
end
