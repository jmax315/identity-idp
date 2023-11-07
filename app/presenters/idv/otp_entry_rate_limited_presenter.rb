module Idv
  class OtpEntryRateLimitedPresenter
    # include ActionView::Helpers::UrlHelper
    # include ActionView::Helpers::TagHelper
    include ActionView::Helpers::TranslationHelper

    attr_reader :sp_name, :user

    def initialize(sp_name:, user:)
      @sp_name = sp_name
      @user = user
    end

    def title
      t('idv.failure.phone.rate_limited.otp_entry.title')
    end

    def reason(countdown)
      t(
        'idv.failure.phone.rate_limited.otp_entry.reason_html',
        countdown: countdown,
        explanation: t('idv.failure.phone.rate_limited.otp_entry.explanation'),
       )
    end

    def exit_action_text
      if sp?
        t('idv.failure.phone.rate_limited.otp_entry.exit.with_sp', app_name: APP_NAME, sp_name: sp_name)
      else
        t('idv.failure.phone.rate_limited.otp_entry.exit.without_sp')
      end
    end

    def troubleshooting_header
      t('idv.failure.phone.rate_limited.otp_entry.troubleshooting_options_heading')
    end

    def contact_support_action_text
      t('idv.troubleshooting.options.contact_support', app_name: APP_NAME)
    end

    private

    def sp?
      sp_name.present?
    end

    # def phone_number_message
    #   t(
    #     "instructions.mfa.#{otp_delivery_preference}.number_message_html",
    #     number_html: content_tag(:strong, phone_number),
    #     expiration: TwoFactorAuthenticatable::DIRECT_OTP_VALID_FOR_MINUTES,
    #   )
    # end

    # private

    # def phone_number
    #   idv_session.user_phone_confirmation_session.phone
    # end

    # def otp_delivery_preference
    #   idv_session.user_phone_confirmation_session.delivery_method
    # end
  end
end
