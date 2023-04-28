RSpec::Matchers.define :have_logged_event do |event, attributes_matcher|
  match do |actual|
    if attributes_matcher.nil?
      expect(actual.events).to have_key(event)
    else
      expect(actual.events[event]).to include(match(attributes_matcher))
    end
  end

  failure_message do |actual|
    matching_events = actual.events[event]
    if matching_events&.length == 1 && attributes_matcher.instance_of?(Hash)
      # We found one matching event. Let's show the user a diff of the actual and expected
      # attributes
      expected = attributes_matcher
      actual = matching_events.first
      message = "Expected that Analytics would have received matching event #{event}\n"
      message += "expected: #{expected}\n"
      message += "     got: #{actual}\n\n"
      message += "Diff:#{differ.diff(actual, expected)}"
      message
    elsif matching_events&.length == 1 &&
          attributes_matcher.instance_of?(RSpec::Matchers::BuiltIn::Include)
      # We found one matching event and an `include` matcher. Let's show the user a diff of the
      # actual and expected attributes
      expected = attributes_matcher.expecteds.first
      actual_attrs = matching_events.first
      actual_compared = actual_attrs.slice(*expected.keys)
      actual_ignored = actual_attrs.except(*expected.keys)
      message = "Expected that Analytics would have received matching event #{event}"
      message += "expected: include #{expected}\n"
      message += "     got: #{actual_attrs}\n\n"
      message += "Diff:#{differ.diff(actual_compared, expected)}\n"
      message += "Attributes ignored by the include matcher:#{differ.diff(
        actual_ignored, {}
      )}"
      message
    else
      <<~MESSAGE
        Expected that Analytics would have received event #{event.inspect}
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
end
