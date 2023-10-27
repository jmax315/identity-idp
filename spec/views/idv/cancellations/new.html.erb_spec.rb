require 'rails_helper'

RSpec::Matchers.define :have_button_to_with_accessibility do |expected_button_text, expected_destination|
  match do |actual_text|
    expected_aria_attributes = "aria-label=\"#{expected_button_text}\""
    begin
      button = Capybara.string(rendered).find_button(expected_button_text)
    rescue Capybara::ElementNotFound
      return false
    end

    button&.has_ancestor?("form[#{expected_aria_attributes}]")
  end

  failure_message do |actual_text|
    begin
      button = Capybara.string(rendered).find_button(expected_button_text)
    rescue Capybara::ElementNotFound
      return "expected to find a button with text '#{expected_button_text}'"
    end

    expected_aria_attributes = "aria-label=\"#{expected_button_text}\""
    expected_form_action = "action=\"#{expected_destination}\""
    expected_attributes = "[#{expected_aria_attributes}][#{expected_form_action}]"

    unless button.has_ancestor?("form#{expected_attributes}")
      return "expected the button to be inside a form with attributes '#{expected_attributes}'. Raw text: #{rendered}"
    end
  end
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

  it 'renders an action to keep going' do
    expect(rendered).to have_button(t('idv.cancel.actions.keep_going'))
  end

  it 'renders action to start over, with the correct aria attributes' do
    expect(rendered).to have_button_to_with_accessibility(
      t('idv.cancel.actions.start_over'),
      idv_cancel_path(step: params[:step]),
    )
  end

  it 'renders action to exit and go to account page' do
    expect(rendered).to have_content(t('idv.cancel.headings.exit.without_sp'))
    t(
      'idv.cancel.description.exit.without_sp',
      app_name: APP_NAME,
      account_page_text: t('idv.cancel.description.account_page'),
    ).each { |expected_p| expect(rendered).to have_content(expected_p) }
    expect(rendered).to have_button(t('idv.cancel.actions.account_page'))
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
