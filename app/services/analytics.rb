# frozen_string_literal: true

class EmptyEventRecorder
  attr_reader :events

  def initialize
    @events = {}
  end

  def record(event, attributes)
  end
end

class EventRecorder < EmptyEventRecorder
  def record(event, attributes)
    attributes_copy = attributes.dup
    if attributes_copy[:proofing_components].instance_of?(Idv::ProofingComponentsLogging)
      attributes_copy[:proofing_components] =
        attributes_copy[:proofing_components].as_json.symbolize_keys
    end
    @events[event] ||= []
    @events[event] << attributes_copy
  end
end

class StubbedNewRelicAgent
  def self.add_custom_attributes(custom_attributes)
  end
end

class StubbedAhoy
  def track(event, analytics_hash)
  end
end

class Analytics
  extend Forwardable
  include AnalyticsEvents
  prepend Idv::AnalyticsEventsEnhancer

  attr_accessor :user
  attr_reader :request, :sp, :ahoy, :irs_session_id, :recorder
  def_delegator :@recorder, :events

  class PiiDetected < StandardError; end

  def self.create_null(user: nil, events: nil, events_enhancer: nil)
    analytics_class = Class.new(Analytics) do
      include events if events
      prepend events_enhancer if events_enhancer

      def idv_final(**kwargs)
        @called_kwargs = kwargs
      end

      attr_reader :called_kwargs
    end

    analytics_class.new(
      user: user || AnonymousUser.new,
      request: OpenStruct.new(
        user_agent: 'some-user-agent',
        headers: {},
      ),
      sp: OpenStruct.new(value: 'some-sp'),
      session: {},
      ahoy: StubbedAhoy.new,
      recorder: EventRecorder.new,
      new_relic_agent: StubbedNewRelicAgent,
    )
  end

  def initialize(user:,
                 request:,
                 sp:,
                 session:,
                 ahoy: nil,
                 irs_session_id: nil,
                 recorder: EmptyEventRecorder.new,
                 new_relic_agent: ::NewRelic::Agent)
    @user = user
    @request = request
    @sp = sp
    @ahoy = ahoy || Ahoy::Tracker.new(request: request)
    @session = session
    @irs_session_id = irs_session_id
    @recorder = recorder
    @new_relic_agent = new_relic_agent
  end

  def track_event(event, attributes = {})
    attributes.delete(:pii_like_keypaths)
    update_session_events_and_paths_visited_for_analytics(event) if attributes[:success] != false
    analytics_hash = {
      event_properties: attributes.except(:user_id),
      new_event: first_event_this_session?,
      path: request&.path,
      session_duration: session_duration,
      user_id: attributes[:user_id] || user.uuid,
      locale: I18n.locale,
    }

    analytics_hash[:irs_session_id] = irs_session_id if irs_session_id
    analytics_hash.merge!(request_attributes) if request

    ahoy.track(event, analytics_hash)

    recorder.record(event, attributes)

    # Tag NewRelic APM trace with a handful of useful metadata
    # https://www.rubydoc.info/github/newrelic/rpm/NewRelic/Agent#add_custom_attributes-instance_method
    @new_relic_agent.add_custom_attributes(
      user_id: analytics_hash[:user_id],
      user_ip: request&.remote_ip,
      service_provider: sp,
      event_name: event,
      git_sha: IdentityConfig::GIT_SHA,
    )
  end

  def update_session_events_and_paths_visited_for_analytics(event)
    @session[:events] ||= {}
    @session[:first_event] = !@session[:events].key?(event)
    @session[:events][event] = true
  end

  def first_event_this_session?
    @session[:first_event]
  end

  def track_mfa_submit_event(attributes)
    multi_factor_auth(
      **attributes,
      pii_like_keypaths: [[:errors, :personal_key], [:error_details, :personal_key]],
    )
  end

  def request_attributes
    attributes = {
      user_ip: request.remote_ip,
      hostname: request.host,
      pid: Process.pid,
      service_provider: sp,
      trace_id: request.headers['X-Amzn-Trace-Id'],
    }

    attributes[:git_sha] = IdentityConfig::GIT_SHA
    if IdentityConfig::GIT_TAG.present?
      attributes[:git_tag] = IdentityConfig::GIT_TAG
    else
      attributes[:git_branch] = IdentityConfig::GIT_BRANCH
    end

    attributes.merge!(browser_attributes)
  end

  def browser
    @browser ||= BrowserCache.parse(request.user_agent)
  end

  def browser_attributes
    {
      user_agent: request.user_agent,
      browser_name: browser.name,
      browser_version: browser.full_version,
      browser_platform_name: browser.platform.name,
      browser_platform_version: browser.platform.version,
      browser_device_name: browser.device.name,
      browser_mobile: browser.device.mobile?,
      browser_bot: browser.bot?,
    }
  end

  def session_duration
    @session[:session_started_at].present? ? Time.zone.now - session_started_at : nil
  end

  def session_started_at
    value = @session[:session_started_at]
    return value unless value.is_a?(String)
    Time.zone.parse(value)
  end

  module PiiAlerter
    def track_event(event, original_attributes = {})
      attributes = original_attributes.dup
      pii_like_keypaths = attributes.delete(:pii_like_keypaths) || []

      constant_name = Analytics.constants.find { |c| Analytics.const_get(c) == event }

      string_payload = attributes.to_json

      if string_payload.include?('pii') && !pii_like_keypaths.include?([:pii])
        raise Analytics::PiiDetected, <<~ERROR
          track_event string 'pii' detected in attributes
          event: #{event} (#{constant_name})
          full event: #{attributes}"
        ERROR
      end

      Idp::Constants::MOCK_IDV_APPLICANT.slice(
        :first_name,
        :last_name,
        :address1,
        :zipcode,
        :dob,
        :state_id_number,
      ).each do |key, default_pii_value|
        if string_payload.match?(Regexp.new('\b' + Regexp.quote(default_pii_value) + '\b', 'i'))
          raise Analytics::PiiDetected, <<~ERROR
            track_event example PII #{key} (#{default_pii_value}) detected in attributes
            event: #{event} (#{constant_name})
            full event: #{attributes}"
          ERROR
        end
      end

      pii_attr_names = Pii::Attributes.members + [:personal_key] - [
        :state, # state on its own is not enough to be a pii leak
      ]

      check_recursive = ->(value, keypath = []) do
        case value
        when Hash
          value.each do |key, val|
            current_keypath = keypath + [key]
            if pii_attr_names.include?(key) && !pii_like_keypaths.include?(current_keypath)
              raise Analytics::PiiDetected, <<~ERROR
                track_event received pii key path: #{current_keypath.inspect}
                event: #{event} (#{constant_name})
                full event: #{attributes.inspect}
                allowlisted keypaths: #{pii_like_keypaths.inspect}
              ERROR
            end

            check_recursive.call(val, [key])
          end
        when Array
          value.each { |val| check_recursive.call(val, keypath) }
        end
      end

      check_recursive.call(attributes)

      super(event, attributes)
    end
  end
end
