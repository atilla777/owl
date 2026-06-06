# frozen_string_literal: true

require 'owl/upgrade/internal/registry_merge'

RSpec.describe Owl::Upgrade::Internal::RegistryMerge do
  let(:seed) do
    {
      'schema_version' => 1,
      'default_workflow' => 'feature',
      'workflows' => {
        'feature' => { 'managed' => true, 'source' => 'workflows/feature/workflow.yaml' }
      }
    }
  end

  it 'refreshes a managed entry from the seed' do
    existing = { 'workflows' => { 'feature' => { 'managed' => true, 'source' => 'old' } } }
    merged, changed = described_class.merge(existing: existing, seed: seed, entries_key: 'workflows')
    expect(changed).to be(true)
    expect(merged.dig('workflows', 'feature', 'source')).to eq('workflows/feature/workflow.yaml')
  end

  it 'preserves a project-owned (managed:false) entry' do
    existing = { 'workflows' => { 'mine' => { 'managed' => false, 'source' => 'workflows/mine/workflow.yaml' } } }
    merged, = described_class.merge(existing: existing, seed: seed, entries_key: 'workflows')
    expect(merged.dig('workflows', 'mine', 'managed')).to be(false)
    expect(merged.dig('workflows', 'feature')).not_to be_nil
  end

  it 'does not clobber a project entry shadowing a seeded key' do
    existing = { 'workflows' => { 'feature' => { 'managed' => false, 'source' => 'mine' } } }
    merged, = described_class.merge(existing: existing, seed: seed, entries_key: 'workflows')
    expect(merged.dig('workflows', 'feature', 'source')).to eq('mine')
  end

  it 'preserves a user-set default_workflow' do
    existing = { 'default_workflow' => 'mine', 'workflows' => {} }
    merged, = described_class.merge(existing: existing, seed: seed, entries_key: 'workflows')
    expect(merged['default_workflow']).to eq('mine')
  end

  it 'reports no change when already in sync' do
    _, changed = described_class.merge(existing: seed, seed: seed, entries_key: 'workflows')
    expect(changed).to be(false)
  end
end
