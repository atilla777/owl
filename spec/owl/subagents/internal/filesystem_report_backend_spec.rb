# frozen_string_literal: true

require 'yaml'

require 'owl/subagents/internal/filesystem_report_backend'

RSpec.describe Owl::Subagents::Internal::FilesystemReportBackend do
  let(:input_bundle) do
    {
      session_type: 'execution',
      tier: 'standard',
      intent: 'Do the thing.',
      context_pack: { task: { id: 'TASK-0001' } },
      output_spec: Owl::Subagents::Internal::OutputSpec.default,
      budget: nil,
      secrets_redactor: nil
    }
  end

  it 'writes the input bundle to .owl/local/spawns/<TASK>/<STEP>.input.yaml' do
    with_tmp_project do |root|
      backend = described_class.new(root: root)
      backend.run(task_id: 'TASK-A', step_id: 'plan', input_bundle: input_bundle)
      path = root + '.owl/local/spawns/TASK-A/plan.input.yaml'
      expect(path.exist?).to be(true)
      parsed = YAML.safe_load(path.read, permitted_classes: [Symbol])
      expect(parsed['session_type']).to eq('execution')
      expect(parsed['intent']).to eq('Do the thing.')
    end
  end

  it 'returns final_state=error with a helpful message when no report exists' do
    with_tmp_project do |root|
      backend = described_class.new(root: root)
      result = backend.run(task_id: 'TASK-B', step_id: 'plan', input_bundle: input_bundle)
      expect(result[:final_state]).to eq(:error)
      expect(result[:report_body]).to be_nil
      expect(result[:error_message]).to include('owl step report')
    end
  end

  it 'returns final_state=returned_normally when a valid report exists' do
    with_tmp_project do |root|
      report_dir = root + '.owl/local/reports/TASK-C'
      report_dir.mkpath
      (report_dir + 'plan.md').write(<<~MD)
        ---
        status: returned_normally
        summary: "OK"
        session_type: execution
        ---

        ## Result

        Plan written.
      MD

      backend = described_class.new(root: root)
      result = backend.run(task_id: 'TASK-C', step_id: 'plan', input_bundle: input_bundle)
      expect(result[:final_state]).to eq(:returned_normally)
      expect(result[:report_body]).to include('## Result')
    end
  end

  it 'returns final_state=error when the existing report fails output_spec validation' do
    with_tmp_project do |root|
      report_dir = root + '.owl/local/reports/TASK-D'
      report_dir.mkpath
      (report_dir + 'plan.md').write('not a valid report')

      backend = described_class.new(root: root)
      result = backend.run(task_id: 'TASK-D', step_id: 'plan', input_bundle: input_bundle)
      expect(result[:final_state]).to eq(:error)
      expect(result[:error_message]).to include('output_spec validation')
    end
  end

  it 'maps the report status field to final_state' do
    with_tmp_project do |root|
      report_dir = root + '.owl/local/reports/TASK-E'
      report_dir.mkpath
      (report_dir + 'plan.md').write(<<~MD)
        ---
        status: interrupted
        summary: "Need help."
        ---

        ## Result

        Stuck.
      MD

      backend = described_class.new(root: root)
      result = backend.run(task_id: 'TASK-E', step_id: 'plan', input_bundle: input_bundle)
      expect(result[:final_state]).to eq(:interrupted)
    end
  end

  it 'maps unrecognized status to :error' do
    with_tmp_project do |root|
      report_dir = root + '.owl/local/reports/TASK-F'
      report_dir.mkpath
      (report_dir + 'plan.md').write(<<~MD)
        ---
        status: budget_exceeded
        summary: "Out of budget."
        ---

        ## Result

        ran out.
      MD

      backend = described_class.new(root: root)
      result = backend.run(task_id: 'TASK-F', step_id: 'plan', input_bundle: input_bundle)
      expect(result[:final_state]).to eq(:budget_exceeded)
    end
  end
end
