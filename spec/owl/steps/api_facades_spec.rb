# frozen_string_literal: true

require 'owl/steps/api'

# Coverage for the thin cli-adapter facades that front
# Steps::Internal::ActiveStepLock / DriftDetector / DriftPolicy. These are
# behavior-preserving pass-throughs (TASK-0040 WS3): the underlying semantics
# are exercised in the Internal specs — here we assert the facade delegates.
RSpec.describe Owl::Steps::Api do
  describe 'active-step lock facades' do
    it 'write + load round-trips a per-task lock' do
      with_tmp_project do |root|
        described_class.active_step_lock_write(
          root: root, task_id: 'TASK-7', step_id: 'plan',
          session_type: 'discussion', variant: 'lite'
        )
        result = described_class.active_step_lock_load(root: root, task_id: 'TASK-7')
        expect(result).to be_ok
        expect(result.value).to include(
          'task_id' => 'TASK-7', 'step_id' => 'plan',
          'session_type' => 'discussion', 'variant' => 'lite'
        )
      end
    end

    it 'load returns Result.ok(nil) when no lock exists' do
      with_tmp_project do |root|
        result = described_class.active_step_lock_load(root: root, task_id: 'TASK-7')
        expect(result).to be_ok
        expect(result.value).to be_nil
      end
    end

    it 'load_sole resolves the single repo-wide lock' do
      with_tmp_project do |root|
        described_class.active_step_lock_write(
          root: root, task_id: 'TASK-9', step_id: 'impl', session_type: 'execution'
        )
        result = described_class.active_step_lock_load_sole(root: root)
        expect(result).to be_ok
        expect(result.value['task_id']).to eq('TASK-9')
      end
    end

    it 'matches? is true only for the locked step' do
      with_tmp_project do |root|
        described_class.active_step_lock_write(
          root: root, task_id: 'TASK-7', step_id: 'plan', session_type: 'discussion'
        )
        lock = described_class.active_step_lock_load(root: root, task_id: 'TASK-7').value
        expect(described_class.active_step_lock_matches?(lock, task_id: 'TASK-7', step_id: 'plan')).to be(true)
        expect(described_class.active_step_lock_matches?(lock, task_id: 'TASK-7', step_id: 'other')).to be(false)
      end
    end

    it 'clear removes an existing lock' do
      with_tmp_project do |root|
        described_class.active_step_lock_write(
          root: root, task_id: 'TASK-7', step_id: 'plan', session_type: 'discussion'
        )
        cleared = described_class.active_step_lock_clear(root: root, task_id: 'TASK-7')
        expect(cleared).to be_ok
        expect(cleared.value).to eq(:cleared)
        expect(described_class.active_step_lock_load(root: root, task_id: 'TASK-7').value).to be_nil
      end
    end
  end

  describe 'drift facades' do
    it 'detect_drift returns [] when the task has no recorded shas' do
      with_tmp_project do |root|
        expect(described_class.detect_drift(root: root, task_id: 'TASK-7', step_id: 'plan')).to eq([])
      end
    end

    it 'drift_policy_for resolves the effective policy' do
      expect(described_class.drift_policy_for(nil)).to eq(:block)
      expect(described_class.drift_policy_for({ 'session_type' => 'discussion' })).to eq(:warn)
      expect(described_class.drift_policy_for(nil, override_ignore: true)).to eq(:ignore)
      expect(
        described_class.drift_policy_for(nil, check: :step_context_frontmatter)
      ).to eq(:warn)
    end
  end
end
