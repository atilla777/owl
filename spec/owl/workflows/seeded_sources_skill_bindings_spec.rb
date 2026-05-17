# frozen_string_literal: true

require 'yaml'
require 'owl/workflows/internal/seeded_sources'

RSpec.describe Owl::Workflows::Internal::SeededSources do
  let(:files) { described_class.files }

  let(:parsed_workflows) do
    files.each_with_object({}) do |entry, memo|
      memo[entry[:relative_path]] = YAML.safe_load(entry[:contents])
    end
  end

  it 'ships six seeded workflows' do
    expect(parsed_workflows.keys).to contain_exactly(
      'workflows/feature/workflow.yaml',
      'workflows/composite_feature/workflow.yaml',
      'workflows/feature_slice/workflow.yaml',
      'workflows/hotfix/workflow.yaml',
      'workflows/research/workflow.yaml',
      'workflows/refactor/workflow.yaml'
    )
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

    it 'uses the `owl-step-<snake>` naming convention' do
      bad = all_steps.reject { |entry| entry[:step]['skill'].to_s.match?(/\Aowl-step-[a-z_]+\z/) }
      expect(bad).to be_empty,
                     -> { "non-conforming skill ids: #{bad.map { |e| "#{e[:path]}##{e[:step]['id']} -> #{e[:step]['skill'].inspect}" }.join(', ')}" }
    end

    it 'binds the skill matching its own step id' do
      mismatched = all_steps.reject do |entry|
        entry[:step]['skill'] == "owl-step-#{entry[:step]['id']}"
      end
      expect(mismatched).to be_empty,
                            -> { "mismatched bindings: #{mismatched.map { |e| "#{e[:path]}##{e[:step]['id']} -> #{e[:step]['skill'].inspect}" }.join(', ')}" }
    end
  end
end
