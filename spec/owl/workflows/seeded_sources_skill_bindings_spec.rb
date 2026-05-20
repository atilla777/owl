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

  it 'ships two seeded workflows' do
    expect(parsed_workflows.keys).to contain_exactly(
      '.owl/workflows/feature/workflow.yaml',
      '.owl/workflows/composite_feature/workflow.yaml'
    )
  end

  it 'materializes a per-step .context.md file alongside every seeded workflow.yaml' do
    parsed_workflows.each do |path, workflow|
      workflow_dir = File.dirname(path)
      Array(workflow['steps']).each do |step|
        expected_path = "#{workflow_dir}/#{step['id']}.context.md"
        entry = files.find { |f| f[:relative_path] == expected_path }
        expect(entry).not_to be_nil,
                             -> { "missing seeded #{expected_path} for step #{step['id']}" }
        expect(entry[:contents]).to include('# Purpose'),
                                    -> { "#{expected_path} missing '# Purpose' heading" }
      end
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

    it 'binds the universal `owl-step-run` skill on every seeded step' do
      mismatched = all_steps.reject { |entry| entry[:step]['skill'] == 'owl-step-run' }
      expect(mismatched).to be_empty,
                            -> { "non-owl-step-run bindings: #{describe_entries(mismatched, 'skill')}" }
    end

    it 'binds a `context_file` named after the step id' do
      mismatched = all_steps.reject do |entry|
        entry[:step]['context_file'] == "#{entry[:step]['id']}.context.md"
      end
      expect(mismatched).to be_empty,
                            -> { "mismatched context_file bindings: #{describe_entries(mismatched, 'context_file')}" }
    end
  end
end
