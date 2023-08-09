class FakeAnalytics < Analytics
  PiiDetected = Class.new(StandardError)

  include AnalyticsEvents
  prepend Idv::AnalyticsEventsEnhancer

  module PiiAlerter
    def track_event(event, original_attributes = {})
      attributes = original_attributes.dup
      pii_like_keypaths = attributes.delete(:pii_like_keypaths) || []

      constant_name = Analytics.constants.find { |c| Analytics.const_get(c) == event }

      string_payload = attributes.to_json

      if string_payload.include?('pii') && !pii_like_keypaths.include?([:pii])
        raise PiiDetected, <<~ERROR
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
          raise PiiDetected, <<~ERROR
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
              raise PiiDetected, <<~ERROR
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

  prepend PiiAlerter

  attr_reader :events
  attr_accessor :user

  def initialize(user: AnonymousUser.new)
    @events = Hash.new
    @user = user
  end

  def track_event(event, attributes = {})
    if attributes[:proofing_components].instance_of?(Idv::ProofingComponentsLogging)
      attributes[:proofing_components] = attributes[:proofing_components].as_json.symbolize_keys
    end
    events[event] ||= []
    events[event] << {
      attributes: attributes,
      backtrace: Thread.current.backtrace,
    }
    nil
  end

  def track_mfa_submit_event(_attributes)
    # no-op
  end

  def browser_attributes
    {}
  end
end

RSpec::Matchers.define :have_logged_event do |event, attributes_matcher|
  match do |actual|
    if attributes_matcher.nil?
      expect(actual.events).to have_key(event)
    else
      attributes_for_events = actual.events[event].pluck(:attributes)
      expect(attributes_for_events).to include(match(attributes_matcher))
    end

    if !allow_multiple_events?
      expect(actual.events[event]).to have_attributes(size: 1)
    end
  end

  chain :at_least_once do
    @allow_multiple_events = true
  end

  failure_message do |actual|
    matching_events = actual.events[event]

    if matching_events&.length.to_i > 1 && !allow_multiple_events?
      <<~MESSAGE
        FakeAnalytics received too many #{event} events.
        expected: 1
        got:      #{matching_events.length}

        Events received:

        #{matching_events.map do |event| 
          <<~EVENT
            at #{first_relevant_backtrace_line(event[:backtrace])}:
            #{event[:attributes].pretty_inspect.split("\n").map { |line| "  #{line}" }.join("\n")},
          EVENT
        end.
        join("\n\n")}

      MESSAGE
    elsif matching_events&.length == 1 && attributes_matcher.instance_of?(Hash)
      # We found one matching event. Let's show the user a diff of the actual and expected
      # attributes
      expected = attributes_matcher
      actual = matching_events.first
      <<~MESSAGE
        Expected that FakeAnalytics would have received matching event #{event}
        expected: #{expected}
             got: #{actual}

        Diff:#{differ.diff(actual, expected)}
      MESSAGE
    elsif matching_events&.length == 1 &&
          attributes_matcher.instance_of?(RSpec::Matchers::BuiltIn::Include)
      # We found one matching event and an `include` matcher. Let's show the user a diff of the
      # actual and expected attributes
      expected = attributes_matcher.expecteds.first
      actual_attrs = matching_events.first
      actual_compared = actual_attrs.slice(*expected.keys)
      actual_ignored = actual_attrs.except(*expected.keys)

      <<~MESSAGE
        Expected that FakeAnalytics would have received matching event #{event}
        expected: include #{expected}
             got: #{actual_attrs}

        Diff:#{differ.diff(actual_compared, expected)}
        Attributes ignored by the include matcher:#{differ.diff(actual_ignored, {})}
      MESSAGE
    else
      <<~MESSAGE
        Expected that FakeAnalytics would have received event #{event.inspect}
        with #{attributes_matcher.inspect}.

        Events received:
        #{actual.events.pretty_inspect}
      MESSAGE
    end
  end

  def differ
    RSpec::Support::Differ.new(
      object_preparer: lambda do |object|
                         RSpec::Matchers::Composable.surface_descriptions_in(object)
                       end,
      color: RSpec::Matchers.configuration.color?,
    )
  end

  def allow_multiple_events?
    !!@allow_multiple_events
  end

  def first_relevant_backtrace_line(backtrace)
    backtrace.
      find do |line|
        is_analytics_code = line.include?('fake_analytics') || line.include?('analytics_events')
        next false if is_analytics_code

        is_app_code = line.start_with?(Rails.root.to_s)

        is_app_code
      end&.
      to_s&.
      sub("#{Rails.root}/", '')
  end
end
