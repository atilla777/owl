# frozen_string_literal: true

require 'owl/subagents/api'

# Coverage for the cli-adapter facades that front
# Subagents::Internal::OutputSpec / ReportPaths (TASK-0040 WS3). Thin
# pass-throughs; the validator/path semantics are covered in the Internal specs.
RSpec.describe Owl::Subagents::Api do
  describe '.report_schema' do
    it 'returns the parsed step_report JSON schema' do
      schema = described_class.report_schema
      expect(schema).to be_a(Hash)
      expect(schema.dig('properties', 'status', 'enum')).to be_a(Array)
    end
  end

  describe '.validate_report' do
    it 'returns Ok for a well-formed report body' do
      body = +"---\n"
      body << "status: returned_normally\n"
      body << "summary: did the thing\n"
      body << "session_type: execution\n"
      body << "---\n\n"
      described_class.report_schema['x-required-sections'].each do |section|
        body << "## #{section}\n\nbody\n\n"
      end
      result = described_class.validate_report(body)
      expect(result).to be_ok
    end

    it 'returns Err for an empty body' do
      result = described_class.validate_report('')
      expect(result).to be_err
      expect(result.code).to eq(:report_empty)
    end
  end

  describe '.report_path' do
    it 'resolves the canonical report path under .owl/local/reports' do
      path = described_class.report_path(root: '/proj', task_id: 'TASK-7', step_id: 'plan')
      expect(path.to_s).to eq('/proj/.owl/local/reports/TASK-7/plan.md')
    end
  end
end
