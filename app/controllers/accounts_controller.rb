class AccountsController < ApplicationController
  include RememberDeviceConcern
  before_action :confirm_two_factor_authenticated
  before_action :confirm_user_is_not_suspended

  layout 'account_side_nav'

  def show
    analytics.account_visit

    states = %w[ AK AL AR AZ CA CO CT DE FL GA
                 HI IA ID IL IN KS KY LA MA MD
                 ME MI MN MO MS MT NC ND NE NH
                 NJ NM NV NY OH OK OR PA RI SC
                 SD TN TX UT VA VT WA WI WV WY ]

    # analytics.idv_doc_auth_verify_proofing_results(
    #   idv_result_to_form_response(
    #     state_id_jurisdiction: states.sample,
    #     result: { success: true },
    #   ),
    # )
    analytics.idv_doc_auth_verify_proofing_results(key: "Hi, mom", state: states.sample)
      # {
      #   :flow_path=>"standard",
      #   :step=>"verify",
      #   :analytics_id=>"Doc Auth",
      #   :irs_reproofing=>false,
      #   :skip_hybrid_handoff=>nil,
      #   :lexisnexis_instant_verify_workflow_ab_test_bucket=>:default,
      #   :acuant_sdk_upgrade_ab_test_bucket=>:default,
      #   :success=>true,
      #   :errors=>{},
      #   :address_edited=>false,
      #   :address_line2_present=>false,
      #   :pii_like_keypaths=>[
      #     [:errors, :ssn],
      #     [:proofing_results, :context, :stages, :resolution, :errors, :ssn],
      #     [:proofing_results, :context, :stages, :residential_address, :errors, :ssn],
      #     [:proofing_results, :context, :stages, :threatmetrix, :response_body, :first_name],
      #     [:same_address_as_id],
      #     [:proofing_results, :context, :stages, :state_id, :state_id_jurisdiction]
      #   ],
      #   :proofing_results=>{
      #     :exception=>nil,
      #     :timed_out=>false,
      #     :threatmetrix_review_status=>"pass",
      #     :context=>{
      #       :device_profiling_adjudication_reason=>"device_profiling_result_pass",
      #       :resolution_adjudication_reason=>"pass_resolution_and_state_id",
      #       :should_proof_state_id=>true,
      #       :stages=>{
      #         :resolution=>{
      #           :success=>true,
      #           :errors=>{},
      #           :exception=>nil,
      #           :timed_out=>false,
      #           :transaction_id=>"resolution-mock-transaction-id-123",
      #           :reference=>"aaa-bbb-ccc",
      #           :can_pass_with_additional_verification=>false,
      #           :attributes_requiring_additional_verification=>[],
      #           :vendor_name=>"ResolutionMock",
      #           :vendor_workflow=>nil
      #         },
      #         :residential_address=>{
      #           :success=>true,
      #           :errors=>{},
      #           :exception=>nil,
      #           :timed_out=>false,
      #           :transaction_id=>"",
      #           :reference=>"",
      #           :can_pass_with_additional_verification=>false,
      #           :attributes_requiring_additional_verification=>[],
      #           :vendor_name=>"ResidentialAddressNotRequired",
      #           :vendor_workflow=>nil
      #         },
      #         :state_id=>{
      #           :success=>true,
      #           :errors=>{},
      #           :exception=>nil,
      #           :mva_exception=>nil,
      #           :timed_out=>false,
      #           :transaction_id=>"state-id-mock-transaction-id-456",
      #           :vendor_name=>"StateIdMock",
      #           :verified_attributes=>[],
      #           :state=>"MT",
      #           :state_id_jurisdiction=>"ND",
      #           :state_id_number=>"#############"
      #         },
      #         :threatmetrix=>{
      #           :client=>nil,
      #           :success=>true,
      #           :errors=>{},
      #           :exception=>nil,
      #           :timed_out=>false,
      #           :transaction_id=>"ddp-mock-transaction-id-123",
      #           :review_status=>"pass",
      #           :response_body=>{
      #             :"fraudpoint.score"=>"500",
      #             :request_id=>"1234",
      #             :request_result=>"success",
      #             :review_status=>"pass",
      #             :risk_rating=>"trusted",
      #             :summary_risk_score=>"-6",
      #             :tmx_risk_rating=>"neutral",
      #             :tmx_summary_reason_code=>["Identity_Negative_History"],
      #             :first_name=>"[redacted]"
      #           }
      #         }
      #       }
      #     }
      #   },
      #   :ssn_is_unique=>false
      # }
    )



    session[:account_redirect_path] = account_path
    cacher = Pii::Cacher.new(current_user, user_session)
    @presenter = AccountShowPresenter.new(
      decrypted_pii: cacher.fetch(current_user.active_or_pending_profile&.id),
      sp_session_request_url: sp_session_request_url_with_updated_params,
      sp_name: decorated_sp_session.sp_name,
      user: current_user,
      locked_for_session: pii_locked_for_session?(current_user),
    )
  end

  def reauthentication
    # This route sends a user through reauthentication and returns them to the account page, since
    # some actions within the account dashboard require a fresh reauthentication (e.g. managing an
    # MFA method or viewing verified profile information).
    user_session[:stored_location] = account_url(params.permit(:manage_authenticator))
    user_session[:context] = 'reauthentication'

    redirect_to login_two_factor_options_path
  end

  private

  def confirm_user_is_not_suspended
    redirect_to user_please_call_url if current_user.suspended?
  end
end
