# frozen_string_literal: true

require 'owl/tasks/internal/task_summary'

RSpec.describe Owl::Tasks::Internal::TaskSummary do
  let(:entry) do
    {
      'id' => 'TASK-0042',
      'title' => 'unify contract',
      'kind' => 'task',
      'priority' => 6,
      'created_at' => '2026-06-26T14:56:16Z',
      'status' => 'open',
      'workflow' => 'refactor',
      # Storage-only noise that the projection must drop unless re-supplied via extra.
      'labels' => %w[health-review],
      'archived_at' => nil
    }
  end

  describe '.project' do
    it 'renames the identity to task_id and keeps the shared core fields' do
      result = described_class.project(entry)
      expect(result).to eq(
        'task_id' => 'TASK-0042',
        'title' => 'unify contract',
        'kind' => 'task',
        'priority' => 6,
        'created_at' => '2026-06-26T14:56:16Z',
        'status' => 'open',
        'workflow' => 'refactor'
      )
    end

    it 'never carries the storage identity key id' do
      expect(described_class.project(entry)).not_to have_key('id')
    end

    it 'emits the core keys in canonical order' do
      expect(described_class.project(entry).keys).to eq(
        %w[task_id title kind priority created_at status workflow]
      )
    end

    it 'merges extra fields after the core, preserving order' do
      result = described_class.project(entry, extra: { 'ready_step_ids' => ['brief'], 'reason' => 'r' })
      expect(result.keys).to eq(
        %w[task_id title kind priority created_at status workflow ready_step_ids reason]
      )
      expect(result['ready_step_ids']).to eq(['brief'])
      expect(result['reason']).to eq('r')
    end

    it 'defaults a missing status to open' do
      expect(described_class.project(entry.merge('status' => nil))['status']).to eq('open')
    end

    it 'coerces a missing or non-integer priority to an Integer' do
      expect(described_class.project(entry.merge('priority' => nil))['priority']).to eq(0)
      expect(described_class.project(entry.merge('priority' => '5'))['priority']).to eq(5)
    end

    it 'stringifies the task_id' do
      expect(described_class.project(entry.merge('id' => :TASK_SYM))['task_id']).to eq('TASK_SYM')
    end
  end
end
