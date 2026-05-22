# frozen_string_literal: true

require 'owl/subagents/api'

RSpec.describe Owl::Subagents::Api do
  let(:valid_context_pack) { { 'task_id' => 'TASK-0001', 'allow_list' => ['owl'] } }
  let(:valid_intent) { 'Generate a report.' }

  describe '.spawn' do
    it 'rejects unknown session_type with invalid_subagent_input' do
      with_tmp_project do |root|
        result = described_class.spawn(
          root: root, task_id: 'TASK-0001', step_id: 'plan',
          session_type: 'research', tier: 'standard',
          intent: valid_intent, context_pack: valid_context_pack
        )
        expect(result).to be_err
        expect(result.code).to eq(:invalid_subagent_input)
        fields = result.details[:errors].map { |e| e[:field] }
        expect(fields).to include('session_type')
      end
    end

    it 'rejects unknown tier with invalid_subagent_input' do
      with_tmp_project do |root|
        result = described_class.spawn(
          root: root, task_id: 'TASK-0001', step_id: 'plan',
          session_type: 'discussion', tier: 'turbo',
          intent: valid_intent, context_pack: valid_context_pack
        )
        expect(result).to be_err
        fields = result.details[:errors].map { |e| e[:field] }
        expect(fields).to include('tier')
      end
    end

    it 'rejects empty intent' do
      with_tmp_project do |root|
        result = described_class.spawn(
          root: root, task_id: 'TASK-0001', step_id: 'plan',
          session_type: 'discussion', tier: 'advanced',
          intent: '   ', context_pack: valid_context_pack
        )
        expect(result).to be_err
        fields = result.details[:errors].map { |e| e[:field] }
        expect(fields).to include('intent')
      end
    end

    it 'rejects non-Hash context_pack' do
      with_tmp_project do |root|
        result = described_class.spawn(
          root: root, task_id: 'TASK-0001', step_id: 'plan',
          session_type: 'discussion', tier: 'advanced',
          intent: valid_intent, context_pack: 'not-a-hash'
        )
        expect(result).to be_err
        fields = result.details[:errors].map { |e| e[:field] }
        expect(fields).to include('context_pack')
      end
    end

    it 'rejects non-Hash output_spec when provided' do
      with_tmp_project do |root|
        result = described_class.spawn(
          root: root, task_id: 'TASK-0001', step_id: 'plan',
          session_type: 'discussion', tier: 'advanced',
          intent: valid_intent, context_pack: valid_context_pack,
          output_spec: 'not-a-hash'
        )
        expect(result).to be_err
        fields = result.details[:errors].map { |e| e[:field] }
        expect(fields).to include('output_spec')
      end
    end

    it 'returns the standard §4.2 output shape when a report exists' do
      with_tmp_project do |root|
        report_dir = root + '.owl/local/reports/TASK-0001'
        report_dir.mkpath
        (report_dir + 'plan.md').write(<<~MD)
          ---
          status: returned_normally
          summary: "Plan complete."
          session_type: execution
          ---

          ## Result

          Generated plan.md.
        MD

        result = described_class.spawn(
          root: root, task_id: 'TASK-0001', step_id: 'plan',
          session_type: 'execution', tier: 'standard',
          intent: valid_intent, context_pack: valid_context_pack
        )
        expect(result).to be_ok
        expect(result.value).to include(
          final_state: :returned_normally,
          report_artifacts: [],
          tool_usage_summary: [],
          error_message: nil
        )
        expect(result.value[:report_body]).to include('## Result')
      end
    end

    it 'forwards to a custom backend when supplied' do
      with_tmp_project do |root|
        captured = nil
        fake_backend = Class.new do
          define_method(:run) do |task_id:, step_id:, input_bundle:, output_spec:| # rubocop:disable Lint/UnusedBlockArgument
            captured = { task_id: task_id, step_id: step_id, bundle: input_bundle, spec: output_spec }
            { final_state: :returned_normally, report_body: 'ok', report_artifacts: [],
              tool_usage_summary: [], error_message: nil }
          end
        end.new

        result = described_class.spawn(
          root: root, task_id: 'TASK-X', step_id: 'sX',
          session_type: 'discussion', tier: 'advanced',
          intent: valid_intent, context_pack: valid_context_pack,
          output_spec: { required_sections: ['Result'] },
          budget: { tokens: 1000 },
          secrets_redactor: { patterns: ['API_KEY'] },
          backend: fake_backend
        )
        expect(result).to be_ok
        expect(result.value[:final_state]).to eq(:returned_normally)
        expect(captured[:task_id]).to eq('TASK-X')
        expect(captured[:bundle][:session_type]).to eq('discussion')
        expect(captured[:bundle][:tier]).to eq('advanced')
        expect(captured[:bundle][:budget]).to eq(tokens: 1000)
        expect(captured[:bundle][:secrets_redactor]).to eq(patterns: ['API_KEY'])
        expect(captured[:bundle][:context_pack]).to eq(valid_context_pack)
      end
    end

    it 'falls back to the default output_spec when none is supplied' do
      with_tmp_project do |root|
        captured_spec = nil
        fake_backend = Class.new do
          define_method(:run) do |task_id:, step_id:, input_bundle:, output_spec:| # rubocop:disable Lint/UnusedBlockArgument
            captured_spec = input_bundle[:output_spec]
            { final_state: :returned_normally, report_body: nil, report_artifacts: [],
              tool_usage_summary: [], error_message: nil }
          end
        end.new

        described_class.spawn(
          root: root, task_id: 'TASK-Y', step_id: 'sY',
          session_type: 'discussion', tier: 'advanced',
          intent: valid_intent, context_pack: valid_context_pack,
          backend: fake_backend
        )
        expect(captured_spec).to include(:required_frontmatter_keys, :required_sections)
      end
    end
  end
end
