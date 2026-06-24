# frozen_string_literal: true

require 'yaml'
require 'owl/workflows/internal/seeded_sources'

RSpec.describe Owl::Workflows::Internal::SeededSources do
  let(:files) { described_class.files }

  let(:workflow_files) do
    files.select { |entry| entry[:relative_path].end_with?('/workflow.yaml') }
  end

  let(:parsed_workflows) do
    workflow_files.to_h { |entry| [entry[:relative_path], YAML.safe_load(entry[:contents])] }
  end

  it 'ships five seeded workflows' do
    expect(parsed_workflows.keys).to contain_exactly(
      '.owl/workflows/feature/workflow.yaml',
      '.owl/workflows/composite_feature/workflow.yaml',
      '.owl/workflows/hotfix/workflow.yaml',
      '.owl/workflows/refactor/workflow.yaml',
      '.owl/workflows/quick/workflow.yaml'
    )
  end

  it 'materializes a per-step .context.md file alongside every seeded workflow.yaml' do
    parsed_workflows.each do |path, workflow|
      workflow_dir = File.dirname(path)
      Array(workflow['steps']).each do |step|
        expected_paths = expected_context_paths_for(workflow_dir: workflow_dir, step: step)
        expected_paths.each do |expected_path|
          entry = files.find { |f| f[:relative_path] == expected_path }
          expect(entry).not_to be_nil,
                               -> { "missing seeded #{expected_path} for step #{step['id']}" }
          expect(entry[:contents]).to include('# Purpose'),
                                      -> { "#{expected_path} missing '# Purpose' heading" }
        end
      end
    end
  end

  def expected_context_paths_for(workflow_dir:, step:)
    if step['variants'].is_a?(Hash) && !step['variants'].empty?
      step['variants'].map { |_, body| "#{workflow_dir}/#{body['context_file']}" }
    else
      ["#{workflow_dir}/#{step['id']}.context.md"]
    end
  end

  describe 'skill bindings' do
    let(:all_steps) do
      parsed_workflows.flat_map do |path, workflow|
        Array(workflow['steps']).map { |step| { path: path, step: step } }
      end
    end

    it 'is non-empty so the spec has something to verify' do
      expect(all_steps).not_to be_empty
    end

    it 'declares a `skill` on every step' do
      missing = all_steps.reject { |entry| entry[:step].key?('skill') }
      expect(missing).to be_empty,
                         -> { "steps without skill: #{missing.map { |e| "#{e[:path]}##{e[:step]['id']}" }.join(', ')}" }
    end

    def describe_entries(entries, field)
      entries.map { |e| "#{e[:path]}##{e[:step]['id']} -> #{e[:step][field].inspect}" }.join(', ')
    end

    ALLOWED_SESSION_TYPES = %w[discussion execution].freeze

    it 'binds the session-typed step skill on every seeded step' do
      mismatched = all_steps.reject do |entry|
        step = entry[:step]
        case step['session_type']
        when 'discussion' then step['skill'] == 'owl-step-discussion'
        when 'execution' then step['skill'] == 'owl-step-execution'
        end
      end
      expect(mismatched).to be_empty,
                            -> { "non-session-typed bindings: #{describe_entries(mismatched, 'skill')}" }
    end

    it 'declares `session_type` on every seeded step' do
      missing = all_steps.reject { |entry| ALLOWED_SESSION_TYPES.include?(entry[:step]['session_type']) }
      expect(missing).to be_empty,
                         -> { "steps without session_type: #{describe_entries(missing, 'session_type')}" }
    end

    it 'binds a `context_file` named after the step id (or a `variants:` block instead)' do
      mismatched = all_steps.reject do |entry|
        step = entry[:step]
        if step['variants'].is_a?(Hash)
          step.key?('default_variant') && step['variants'].key?(step['default_variant'])
        else
          step['context_file'] == "#{step['id']}.context.md"
        end
      end
      expect(mismatched).to be_empty,
                            -> { "mismatched context bindings: #{describe_entries(mismatched, 'context_file')}" }
    end
  end
end
