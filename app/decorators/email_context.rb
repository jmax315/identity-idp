class EmailContext
  attr_reader :user, :email_id

  def initialize(user, email_id)
    @user = user
    binding.pry
    @email_id = email_id
  end

  def last_sign_in_email_address
    user.confirmed_email_addresses.order('last_sign_in_at DESC NULLS LAST').first
  end

  # The following is a proof of concept placeholder function
  def last_sign_in_email_address_session
    email_address&.email || EmailAddress.confirmed.where(user_id: user_id).order_by(id: email_id).first
  end

  def email_address
    @email_address ||= EmailAddress.find(email_id)
  end

  def email_address_count
    user.email_addresses.count
  end

  def confirmed_email_address_count
    user.confirmed_email_addresses.count
  end
end
