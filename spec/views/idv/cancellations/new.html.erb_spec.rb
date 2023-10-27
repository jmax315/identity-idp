require 'rails_helper'

class HaveButtonToWithAccessibilityMatcher
  def initialize(expected_button_text, expected_action)
    @expected_button_text = expected_button_text
    @expected_action = expected_action
  end

  def match(actual_text)
    @actual_text = actual_text
    button&.has_ancestor?("form#{expected_attributes}")
  end

  def failure_message(actual_text)
    @actual_text = actual_text

    message = ''
    if button
      unless button.has_ancestor?("form#{expected_attributes}")
        message += "expected the button to be inside a form with attributes '#{expected_attributes}'."
      end
    else
      message  += "expected to find a button with text '#{@expected_button_text}'"
    end

    return message + "\n" + actual_text
  end

  private

  def button
    Capybara.string(@actual_text).find_button(@expected_button_text)
  rescue Capybara::ElementNotFound
    return nil
  end

  def expected_aria_attributes
    "aria-label=\"#{@expected_button_text}\""
  end

  def expected_form_action
    "action=\"#{@expected_action}\""
  end

  def expected_attributes
    "[#{expected_aria_attributes}][#{expected_form_action}]"
  end
end

RSpec::Matchers.define :have_button_to_with_accessibility do |expected_button_text, expected_action|
  matcher = HaveButtonToWithAccessibilityMatcher.new(expected_button_text, expected_action)
  match { |actual_text| matcher.match(actual_text) }
  failure_message { |actual_text| matcher.failure_message(actual_text) }
end

RSpec.describe 'idv/cancellations/new.html.erb' do
  let(:hybrid_session) { false }
  let(:params) { ActionController::Parameters.new }
  let(:sp_name) { nil }
  let(:presenter) { Idv::CancellationsPresenter.new(sp_name: sp_name, url_options: {}) }

  before do
    assign(:hybrid_session, hybrid_session)
    assign(:presenter, presenter)
    allow(view).to receive(:params).and_return(params)

    render
  end

  it 'renders an action to keep going, with the correct aria attributes' do
    expect(rendered).to have_button_to_with_accessibility(
      t('idv.cancel.actions.keep_going'),
      idv_cancel_path(step: params[:step]),
    )
  end

  it 'renders action to start over, with the correct aria attributes' do
    expect(rendered).to have_button_to_with_accessibility(
      t('idv.cancel.actions.start_over'),
      idv_session_path(step: params[:step]),
    )
  end

  it 'renders action to exit and go to account page, with the correct aria attributes' do
    expect(rendered).to have_content(t('idv.cancel.headings.exit.without_sp'))
    t(
      'idv.cancel.description.exit.without_sp',
      app_name: APP_NAME,
      account_page_text: t('idv.cancel.description.account_page'),
    ).each { |expected_p| expect(rendered).to have_content(expected_p) }

    expect(rendered).to have_button_to_with_accessibility(
      t('idv.cancel.actions.account_page'),
      idv_cancel_path(step: params[:step], location: 'cancel'),
    )
  end

  context 'with hybrid flow' do
    let(:hybrid_session) { true }

    it 'renders heading' do
      expect(rendered).to have_text(t('idv.cancel.headings.prompt.hybrid'))
    end

    it 'renders content' do
      expect(rendered).to have_text(t('idv.cancel.description.hybrid'))
    end
  end

  context 'with step parameter' do
    let(:params) { ActionController::Parameters.new(step: 'first') }

    it 'forwards step to confirmation link' do
      expect(rendered).to have_selector(
        "[action='#{idv_cancel_path(step: 'first', location: 'cancel')}']",
      )
    end
  end

  context 'with associated sp' do
    let(:sp_name) { 'Example SP' }

    it 'renders action to exit and return to SP' do
      expect(rendered).to have_content(
        t('idv.cancel.headings.exit.with_sp', app_name: APP_NAME, sp_name: sp_name),
      )
      t(
        'idv.cancel.description.exit.with_sp_html',
        app_name: APP_NAME,
        sp_name: sp_name,
        account_page_link_html: t('idv.cancel.description.account_page'),
      ).each { |expected_p| expect(rendered).to have_content(expected_p) }
      expect(rendered).to have_button(t('idv.cancel.actions.exit', app_name: APP_NAME))
    end
  end
end
