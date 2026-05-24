# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'tmpdir'

require 'owl/steps/internal/active_step_lock'

RSpec.describe Owl::Steps::Internal::ActiveStepLock do
  let(:root_holder) { { root: nil } }
  let(:root) { root_holder[:root] }

  around do |example|
    Dir.mktmpdir('owl-lock-spec') do |dir|
      root_holder[:root] = Pathname.new(dir)
      example.run
    end
  end

  describe '.path' do
    it 'returns .owl/local/active_step.yaml under root' do
      expect(described_class.path(root: root).to_s).to end_with('.owl/local/active_step.yaml')
    end
  end

  describe '.load' do
    it 'returns Result.ok(nil) when the lock file does not exist' do
      result = described_class.load(root: root)
      expect(result).to be_ok
      expect(result.value).to be_nil
    end

    it 'returns Result.ok(payload) for a valid lock' do
      described_class.write(
        root: root, task_id: 'TASK-7', step_id: 'plan', session_type: 'discussion'
      )
      result = described_class.load(root: root)
      expect(result).to be_ok
      expect(result.value).to include(
        'schema_version' => 1,
        'task_id' => 'TASK-7',
        'step_id' => 'plan',
        'session_type' => 'discussion'
      )
      expect(result.value['declared_at']).to be_a(String)
    end

    it 'returns Result.err on invalid YAML' do
      path = described_class.path(root: root)
      path.dirname.mkpath
      File.write(path.to_s, "not a mapping: : :\n  - x: y: z")
      result = described_class.load(root: root)
      expect(result).to be_err
      expect(result.code).to eq(:active_step_lock_invalid)
    end
  end

  describe '.write' do
    it 'creates the lock file with mkdir_p' do
      result = described_class.write(
        root: root, task_id: 'TASK-1', step_id: 'implement',
        session_type: 'execution', variant: 'feature'
      )
      expect(result).to be_ok
      payload = YAML.safe_load(described_class.path(root: root).read)
      expect(payload['variant']).to eq('feature')
      expect(payload['session_type']).to eq('execution')
    end

    it 'omits variant when not provided' do
      described_class.write(
        root: root, task_id: 'TASK-2', step_id: 'design', session_type: 'discussion'
      )
      payload = YAML.safe_load(described_class.path(root: root).read)
      expect(payload).not_to have_key('variant')
    end
  end

  describe '.clear' do
    it 'returns Result.ok(:absent) when no lock exists' do
      result = described_class.clear(root: root)
      expect(result).to be_ok
      expect(result.value).to eq(:absent)
    end

    it 'removes the lock file when present' do
      described_class.write(
        root: root, task_id: 'TASK-3', step_id: 'plan', session_type: 'execution'
      )
      expect(described_class.path(root: root)).to exist
      result = described_class.clear(root: root)
      expect(result).to be_ok
      expect(result.value).to eq(:cleared)
      expect(described_class.path(root: root)).not_to exist
    end
  end

  describe '.matches?' do
    let(:payload) { { 'task_id' => 'TASK-4', 'step_id' => 'plan' } }

    it 'returns true when both ids match' do
      expect(described_class.matches?(payload, task_id: 'TASK-4', step_id: 'plan')).to be true
    end

    it 'returns false when task_id differs' do
      expect(described_class.matches?(payload, task_id: 'TASK-X', step_id: 'plan')).to be false
    end

    it 'returns false when step_id differs' do
      expect(described_class.matches?(payload, task_id: 'TASK-4', step_id: 'design')).to be false
    end

    it 'returns false for a non-Hash payload' do
      expect(described_class.matches?(nil, task_id: 'TASK-4', step_id: 'plan')).to be false
    end
  end
end
