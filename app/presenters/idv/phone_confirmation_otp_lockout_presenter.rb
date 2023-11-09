class Idv::PhoneConfirmationOtpLockoutPresenter
  include ActionView::Helpers::TranslationHelper

  attr_reader :type, :user

  def initialize(user)
    @user = user
  end

  def title
    'Try again later'
  end

  def reason(countdown_timer)
    'You entered an incorrect one-time code too many times. ' \
      'You will have to start over verifying your identinty from the beginning. ' \
      "<strong>Try again in #{countdown_timer}.</strong>".html_safe
  end
  
  def exit_action_text
    'Exit Login.gov and return to <Partner Agency>'
  end

  def troubleshooting_header
    "Need immediate assistance? Here's how to get help:"
  end

  def contact_support_action_text
    'Contact Login.gov Support'
  end
end
