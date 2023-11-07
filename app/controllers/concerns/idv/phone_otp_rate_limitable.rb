module Idv
  module PhoneOtpRateLimitable
    extend ActiveSupport::Concern

    included do
      before_action :handle_locked_out_user
    end

    def handle_locked_out_user
      reset_attempt_count_if_user_no_longer_locked_out
      return unless current_user.locked_out?
      analytics.idv_phone_confirmation_otp_rate_limit_locked_out
      handle_too_many_otp_attempts
      false
    end

    def reset_attempt_count_if_user_no_longer_locked_out
      return unless current_user.no_longer_locked_out?

      UpdateUser.new(
        user: current_user,
        attributes: {
          second_factor_attempts_count: 0,
          second_factor_locked_at: nil,
        },
      ).call
    end

    def handle_too_many_otp_sends
      analytics.idv_phone_confirmation_otp_rate_limit_sends
      irs_attempts_api_tracker.idv_phone_otp_sent_rate_limited
      handle_max_attempts('otp_requests')
    end

    def handle_too_many_otp_attempts
      analytics.idv_phone_confirmation_otp_rate_limit_attempts
      handle_max_attempts('otp_phone_confirmation_attempts')
    end

    def handle_max_attempts(type)
      if type == 'otp_phone_confirmation_attempts'
        presenter = Idv::OtpEntryRateLimitedPresenter.new(
          sp_name: decorated_sp_session.sp_name,
          user: current_user,
        )
        path = 'idv/phone_errors/_otp_too_many_entries'
      else
        presenter = TwoFactorAuthCode::MaxAttemptsReachedPresenter.new(
          type,
          current_user,
        )
        path = 'two_factor_authentication/_locked'
      end

      render_full_width(path, locals: { presenter: presenter })
    end
  end
end
