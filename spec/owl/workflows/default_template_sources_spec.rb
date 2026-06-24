# frozen_string_literal: true

require 'yaml'

require 'pathname'

require 'owl/workflows/internal/default_template'
require 'owl/workflows/internal/seeded_sources'

GEM_ROOT_FOR_DEFAULT_TEMPLATE = Pathname.new(File.expand_path('../../..', __dir__))

# Guards the invariant that the default workflow registry shipped to fresh
# consumer projects (`DefaultTemplate.render`) never lists a workflow whose
# `source:` is missing from the seeded sources that `owl init` actually
# materializes. A drift here gives a freshly-initialized project a registry
# entry pointing at a non-existent workflow.yaml (TASK-0020).
RSpec.describe Owl::Workflows::Internal::DefaultTemplate do
  let(:registry) { YAML.safe_load(described_class.render) }

  let(:seeded_relative_paths) do
    Owl::Workflows::Internal::SeededSources.files.map { |entry| entry[:relative_path] }
  end

  it 'registers exactly the five shipped workflows' do
    expect(registry['workflows'].keys).to contain_exactly(
      'feature', 'composite_feature', 'hotfix', 'refactor', 'quick'
    )
  end

  it 'marks every registered workflow as a managed, enabled seed at version 1.0' do
    registry['workflows'].each_value do |entry|
      expect(entry['enabled']).to be(true)
      expect(entry['managed']).to be(true)
      expect(entry['version']).to eq('1.0')
      expect(entry['title']).to be_a(String).and(satisfy('non-empty') { |t| !t.empty? })
    end
  end

  it 'points every registered source at a workflow.yaml that exists on disk' do
    registry['workflows'].each do |key, entry|
      source = entry['source']
      expect(source).to eq("workflows/#{key}/workflow.yaml")
      expect(GEM_ROOT_FOR_DEFAULT_TEMPLATE.join(source)).to exist,
                                                            "missing seed source for #{key}: #{source}"
    end
  end

  it 'ships a seeded source (under .owl/workflows) for every registered workflow' do
    registry['workflows'].each_key do |key|
      expect(seeded_relative_paths).to include(".owl/workflows/#{key}/workflow.yaml"),
                                       "registry key #{key} has no materialized seed source"
    end
  end
end
