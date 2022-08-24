require 'rails_helper'

RSpec.describe Proofing::Mock::DdpMockClient do
  let(:applicant) {
    Idp::Constants::MOCK_IDV_APPLICANT_WITH_SSN.merge(threatmetrix_session_id: 'ABCD-1234')
  }

  subject(:instance) { described_class.new }

  describe '#proof' do
    subject(:result) { instance.proof(applicant) }

    it 'passes by default' do
      expect(result.review_status).to eq('pass')
    end

    context 'with magic "reject" SSN' do
      let(:applicant) { super().merge(ssn: '666-77-8888') }
      it 'fails' do
        expect(result.review_status).to eq('reject')
      end
    end

    context 'with magic "review" SSN' do
      let(:applicant) { super().merge(ssn: '666-77-9999') }
      it 'fails' do
        expect(result.review_status).to eq('review')
      end
    end

    context 'with magic "nil" SSN' do
      let(:applicant) { super().merge(ssn: '666-77-0000') }
      it 'fails' do
        expect(result.review_status).to be_nil
      end
    end
  end
end
