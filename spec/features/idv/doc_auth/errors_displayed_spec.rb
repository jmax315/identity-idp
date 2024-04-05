require 'rails_helper'

RSpec.feature 'error messages displayed', js: true, allowed_extra_analytics: [:*] do
  include IdvStepHelper
  include DocAuthHelper
  include DocCaptureHelper

  let(:user) { user_with_2fa }
  let(:sp_name) { 'Test SP' }

  before do
    allow_any_instance_of(ServiceProviderSession).to receive(:sp_name).and_return(sp_name)
  end

  context 'standard desktop flow' do
    # noop
  end

  context 'standard mobile flow', allow_browser_log: true do
    context 'when a selfie is not requested by SP' do
      # noop
    end

    context 'when a selfie is required by the SP' do
      # assume IPP is enabled - TODO
      before do
        allow_any_instance_of(FederatedProtocols::Oidc).
          to receive(:biometric_comparison_required?).
          and_return(true)
        expect(FeatureManagement).to receive(:idv_allow_selfie_check?).at_least(:once).
          and_return(selfie_check_enabled)
        perform_in_browser(:mobile) do
          visit_idp_from_oidc_sp_with_ial2(biometric_comparison_required: true)
          sign_in_and_2fa_user(user)
          complete_doc_auth_steps_before_document_capture_step
        end
      end

      let(:selfie_check_enabled) { true }
      
      # done
      context 'when doc auth result is failed' do
        it 'displays the expected h1, body copy, and inline errors' do
          perform_in_browser(:mobile) do
            attach_images(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_credential_doc_auth_fail_selfie_pass.yml'
              ),
            )
            attach_selfie(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_credential_doc_auth_fail_selfie_pass.yml'
              ),
            )

            submit_images

            h1_error_message = strip_tags(t('errors.doc_auth.rate_limited_heading'))
            expect(page).to have_content(h1_error_message)

            body_error_message = strip_tags(t('doc_auth.errors.dpi.top_msg'))
            expect(page).to have_content(body_error_message)

            click_try_again
            expect(page).to have_current_path(idv_document_capture_path)

            inline_error_message = strip_tags(t('doc_auth.errors.dpi.failed_short'))
            expect(page).to have_content(inline_error_message)
          end
        end
      end

      #   come back to this one
      # mostly done but can't find inline message
      context 'when doc auth result passes but liveness fails' do
        it 'displays the expected h1, body copy, and inline errors' do
          perform_in_browser(:mobile) do
            attach_images(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_credential_no_liveness.yml'
              ),
            )
            attach_selfie(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_credential_no_liveness.yml'
              ),
            )

            submit_images

            h1_error_message = strip_tags(t('errors.doc_auth.selfie_not_live_or_poor_quality_heading'))
            expect(page).to have_content(h1_error_message)

            body_error_message = strip_tags(t('doc_auth.errors.alerts.selfie_not_live'))
            expect(page).to have_content(body_error_message)

            click_try_again
            expect(page).to have_current_path(idv_document_capture_path)

            #   come back to this one
            # inline error might have been deleted
            # selfie_not_live_poor_quality
            # https://github.com/18F/identity-idp/blob/e1428dd0de40bc5f088fe27c707b4f6b9306d256/config/locales/doc_auth/en.yml

            # Looks like it should be:
            #   "We couldn’t verify the photo of yourself. Try taking a new picture."
            #   but I can't find this message
            # inline_error_message = strip_tags(t('doc_auth.errors.general.selfie_failure'))
            # expect(page).to have_content(inline_error_message)
          end
        end
      end

      # done but maybe add all 3 inline errors?
      context 'when doc auth result and liveness pass but face match fails' do
        it 'displays the expected h1, body copy, and inline errors' do
          perform_in_browser(:mobile) do
            attach_images(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_portrait_match_failure.yml'
              ),
            )
            attach_selfie(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_portrait_match_failure.yml'
              ),
            )

            submit_images

            h1_error_message = strip_tags(t('errors.doc_auth.selfie_fail_heading'))
            expect(page).to have_content(h1_error_message)

            body_error_message = strip_tags(t('doc_auth.errors.general.selfie_failure'))
            expect(page).to have_content(body_error_message)

            click_try_again
            expect(page).to have_current_path(idv_document_capture_path)

            inline_error_message = strip_tags(t('doc_auth.errors.general.multiple_front_id_failures'))
            expect(page).to have_content(inline_error_message)
          end
        end
      end

      # done but maybe add all 3 inline errors?
      context 'when doc auth, liveness, and face match pass but PII validation fails' do
        it 'displays the expected h1, body copy, and inline errors' do
          perform_in_browser(:mobile) do
            attach_images(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_credential_doc_auth_selfie_pass_pii_fail.yml'
              ),
            )
            attach_selfie(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_credential_doc_auth_selfie_pass_pii_fail.yml'
              ),
            )

            submit_images

            h1_error_message = strip_tags(t('errors.doc_auth.rate_limited_heading'))
            expect(page).to have_content(h1_error_message)

            body_error_message = strip_tags(t('doc_auth.errors.alerts.address_check'))
            expect(page).to have_content(body_error_message)

            click_try_again
            expect(page).to have_current_path(idv_document_capture_path)

            inline_error_message = strip_tags(t('doc_auth.errors.general.multiple_front_id_failures'))
            expect(page).to have_content(inline_error_message)
          end
        end
      end

      # done but failing
      context 'when there are both doc auth errors and liveness errors' do
        it 'displays the expected h1, body copy, and inline errors' do
          perform_in_browser(:mobile) do
            attach_images(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_credential_doc_auth_fail_and_no_liveness.yml'
              ),
            )
            attach_selfie(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_credential_doc_auth_fail_and_no_liveness.yml'
              ),
            )

            submit_images

            h1_error_message = strip_tags(t('errors.doc_auth.rate_limited_heading'))
            expect(page).to have_content(h1_error_message)

            body_error_message = strip_tags(t('doc_auth.errors.dpi.top_msg'))
            expect(page).to have_content(body_error_message)

            click_try_again
            expect(page).to have_current_path(idv_document_capture_path)

            inline_error_message = strip_tags(t('doc_auth.errors.dpi.failed_short'))
            expect(page).to have_content(inline_error_message)
          end
        end
      end

      # done but failing
      context 'when there are both doc auth errors and face match errors' do
        it 'displays the expected h1, body copy, and inline errors' do
          perform_in_browser(:mobile) do
            attach_images(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_credential_doc_auth_fail_face_match_fail.yml'
              ),
            )
            attach_selfie(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_credential_doc_auth_fail_face_match_fail.yml'
              ),
            )

            submit_images

            h1_error_message = strip_tags(t('errors.doc_auth.rate_limited_heading'))
            expect(page).to have_content(h1_error_message)

            body_error_message = strip_tags(t('doc_auth.errors.dpi.top_msg'))
            expect(page).to have_content(body_error_message)

            click_try_again
            expect(page).to have_current_path(idv_document_capture_path)

            inline_error_message = strip_tags(t('doc_auth.errors.dpi.failed_short'))
            expect(page).to have_content(inline_error_message)
          end
        end
      end

      # done but failing
      context 'when there is a doc auth error on one side of the ID and face match errors' do
        it 'displays the expected h1, body copy, and inline errors' do
          perform_in_browser(:mobile) do
            attach_images(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_credential_back_fail_doc_auth_face_match_errors.yml'
              ),
            )
            attach_selfie(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_credential_back_fail_doc_auth_face_match_errors.yml'
              ),
            )

            submit_images

            h1_error_message = strip_tags(t('errors.doc_auth.rate_limited_heading'))
            expect(page).to have_content(h1_error_message)

            body_error_message = strip_tags(t('doc_auth.errors.alerts.barcode_content_check'))
            expect(page).to have_content(body_error_message)

            click_try_again
            expect(page).to have_current_path(idv_document_capture_path)

            inline_error_message = strip_tags(t('doc_auth.errors.general.fallback_field_level'))
            expect(page).to have_content(inline_error_message)
          end
        end
      end

      # done but failing
      context 'when there is a doc auth error on one side of the ID and a liveness error' do
        it 'displays the expected h1, body copy, and inline errors' do
          perform_in_browser(:mobile) do
            attach_images(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_credential_back_fail_doc_auth_face_match_errors.yml'
              ),
            )
            attach_selfie(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_credential_back_fail_doc_auth_face_match_errors.yml'
              ),
            )

            submit_images

            h1_error_message = strip_tags(t('errors.doc_auth.rate_limited_heading'))
            expect(page).to have_content(h1_error_message)

            body_error_message = strip_tags(t('doc_auth.errors.alerts.barcode_content_check'))
            expect(page).to have_content(body_error_message)

            click_try_again
            expect(page).to have_current_path(idv_document_capture_path)

            inline_error_message = strip_tags(t('doc_auth.errors.general.fallback_field_level'))
            expect(page).to have_content(inline_error_message)
          end
        end
      end

      # mostly done, come back to this one when liveness inline error fixed
      context 'when there are both liveness errors and face match errors' do
        it 'displays the expected h1, body copy, and inline errors' do
          perform_in_browser(:mobile) do
            attach_images(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_credential_liveness_fail_face_match_fail.yml'
              ),
            )
            attach_selfie(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_credential_liveness_fail_face_match_fail.yml'
              ),
            )

            submit_images

            h1_error_message = strip_tags(t('errors.doc_auth.selfie_not_live_or_poor_quality_heading'))
            expect(page).to have_content(h1_error_message)

            body_error_message = strip_tags(t('doc_auth.errors.alerts.selfie_not_live'))
            expect(page).to have_content(body_error_message)

            click_try_again
            expect(page).to have_current_path(idv_document_capture_path)

            #   come back to this one
            # inline error might have been deleted
            # selfie_not_live_poor_quality
            # https://github.com/18F/identity-idp/blob/e1428dd0de40bc5f088fe27c707b4f6b9306d256/config/locales/doc_auth/en.yml

            # Looks like it should be:
            #   "We couldn’t verify the photo of yourself. Try taking a new picture."
            #   but I can't find this message
            # inline_error_message = strip_tags(t('doc_auth.errors.general.selfie_failure'))
            # expect(page).to have_content(inline_error_message)
          end
        end
      end

      # done and passing but if we checked inline error for selfie would fail
      context 'when there are both face match errors and pii errors' do
        it 'displays the expected h1, body copy, and inline errors' do
          perform_in_browser(:mobile) do
            attach_images(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_credential_face_match_fail_and_pii_fail.yml'
              ),
            )
            attach_selfie(
              Rails.root.join(
                'spec', 'fixtures',
                'ial2_test_credential_face_match_fail_and_pii_fail.yml'
              ),
            )

            submit_images

            h1_error_message = strip_tags(t('errors.doc_auth.selfie_fail_heading'))
            expect(page).to have_content(h1_error_message)

            body_error_message = strip_tags(t('doc_auth.errors.general.selfie_failure'))
            expect(page).to have_content(body_error_message)

            click_try_again
            expect(page).to have_current_path(idv_document_capture_path)

            inline_error_message = strip_tags(t('doc_auth.errors.general.multiple_front_id_failures'))
            expect(page).to have_content(inline_error_message)
          end
        end
      end

      # Are there any combinations you think might be missing?
      # Come back to retaking a photo
      # doc_auth.errors vs errors.doc_auth
    end
  end
end
