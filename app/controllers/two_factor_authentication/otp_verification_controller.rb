module TwoFactorAuthentication
  class OtpVerificationController < ApplicationController
    include TwoFactorAuthenticatable
    include MfaSetupConcern

    before_action :check_sp_required_mfa
    before_action :confirm_multiple_factors_enabled
    before_action :redirect_if_blank_phone, only: [:show]
    before_action :confirm_voice_capability, only: [:show]

    helper_method :in_multi_mfa_selection_flow?

    def show
      analytics.multi_factor_auth_enter_otp_visit(**analytics_properties)

      @landline_alert = landline_warning?
      @presenter = presenter_for_two_factor_authentication_method
    end

    def create
      result = otp_verification_form.submit
      post_analytics(result)
      if result.success?
        handle_valid_otp(next_url: nil, auth_method: params[:otp_delivery_preference])
      else
        handle_invalid_otp(context: context, type: 'otp')
      end
    end

    private

    def otp_verification_form
      OtpVerificationForm.new(current_user, sanitized_otp_code)
    end

    def redirect_if_blank_phone
      return if phone.present?

      flash[:error] = t('errors.messages.phone_required')
      redirect_to new_user_session_path
    end

    def confirm_multiple_factors_enabled
      return if UserSessionContext.confirmation_context?(context)
      phone_enabled = phone_enabled?
      return if phone_enabled

      if MfaPolicy.new(current_user).two_factor_enabled? &&
         !phone_enabled && user_signed_in?
        return redirect_to user_two_factor_authentication_url
      end

      redirect_to phone_setup_url
    end

    def phone_enabled?
      TwoFactorAuthentication::PhonePolicy.new(current_user).enabled?
    end

    def landline_warning?
      user_session[:phone_type] == 'landline' && params[:otp_delivery_preference] == 'sms'
    end

    def confirm_voice_capability
      return if params[:otp_delivery_preference] == 'sms'

      phone_is_confirmed = UserSessionContext.authentication_or_reauthentication_context?(context)

      capabilities = PhoneNumberCapabilities.new(phone, phone_confirmed: phone_is_confirmed)

      return if capabilities.supports_voice?

      flash[:error] = t(
        'two_factor_authentication.otp_delivery_preference.voice_unsupported',
        location: capabilities.unsupported_location,
      )
      redirect_to login_two_factor_url(otp_delivery_preference: 'sms', reauthn: reauthn?)
    end

    def phone
      phone_configuration&.phone ||
        user_session[:unconfirmed_phone]
    end

    def phone_configuration
      return @phone_configuration if defined?(@phone_configuration)
      @phone_configuration =
        MfaContext.new(current_user).phone_configuration(user_session[:phone_id])
    end

    def sanitized_otp_code
      form_params[:code].to_s.strip.sub(/^#/, '')
    end

    def form_params
      params.permit(:code)
    end

    def post_analytics(result)
      properties = result.to_h.merge(analytics_properties)
      analytics.multi_factor_auth_setup(**properties) if context == 'confirmation'

      analytics.track_mfa_submit_event(properties)

      if UserSessionContext.reauthentication_context?(context)
        irs_attempts_api_tracker.mfa_login_phone_otp_submitted(
          reauthentication: true,
          success: properties[:success],
        )
      elsif UserSessionContext.authentication_or_reauthentication_context?(context)
        irs_attempts_api_tracker.mfa_login_phone_otp_submitted(
          reauthentication: false,
          success: properties[:success],
        )
      elsif UserSessionContext.confirmation_context?(context)
        irs_attempts_api_tracker.mfa_enroll_phone_otp_submitted(
          success: properties[:success],
        )
      end
    end

    def sign_up_mfa_selection_order_bucket
      return unless in_multi_mfa_selection_flow?
      @sign_up_mfa_selection_order_bucket = AbTests::SIGN_UP_MFA_SELECTION.bucket(current_user.uuid)
    end

    def analytics_properties
      parsed_phone = Phonelib.parse(phone)

      {
        context: context,
        multi_factor_auth_method: params[:otp_delivery_preference],
        confirmation_for_add_phone: confirmation_for_add_phone?,
        area_code: parsed_phone.area_code,
        country_code: parsed_phone.country,
        phone_fingerprint: Pii::Fingerprinter.fingerprint(parsed_phone.e164),
        phone_configuration_id: phone_configuration&.id,
        in_multi_mfa_selection_flow: in_multi_mfa_selection_flow?,
        enabled_mfa_methods_count: mfa_context.enabled_mfa_methods_count,
        sign_up_mfa_priority_bucket: sign_up_mfa_selection_order_bucket,
      }
    end

    def presenter_for_two_factor_authentication_method
      TwoFactorAuthCode::PhoneDeliveryPresenter.new(
        data: phone_view_data,
        view: view_context,
        service_provider: current_sp,
        remember_device_default: remember_device_default,
      )
    end

    def phone_view_data
      {
        confirmation_for_add_phone: confirmation_for_add_phone?,
        phone_number: display_phone_to_deliver_to,
        code_value: direct_otp_code,
        otp_expiration: otp_expiration,
        otp_delivery_preference: params[:otp_delivery_preference],
        otp_make_default_number: selected_otp_make_default_number,
        unconfirmed_phone: unconfirmed_phone?,
      }.merge(generic_data)
    end

    def check_sp_required_mfa
      check_sp_required_mfa_bypass(auth_method: params[:otp_delivery_preference])
    end
  end
end
