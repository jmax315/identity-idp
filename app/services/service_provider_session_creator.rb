# frozen_string_literal: true

class ServiceProviderSessionCreator
  def initialize(sp:, view_context:, sp_session:, service_provider_request:)
    @sp = sp
    @view_context = view_context
    @sp_session = sp_session
    @service_provider_request = service_provider_request
  end

  def create_session
    if sp
      ServiceProviderSession.new(
        sp: sp,
        view_context: view_context,
        sp_session: sp_session,
        service_provider_request: service_provider_request,
      )
    else
      NullServiceProviderSession.new(view_context: view_context)
    end
  end

  private

  attr_reader :sp, :view_context, :sp_session, :service_provider_request
end
