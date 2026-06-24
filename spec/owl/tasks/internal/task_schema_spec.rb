# frozen_string_literal: true

require 'owl/tasks/internal/task_schema'

RSpec.describe Owl::Tasks::Internal::TaskSchema do
  describe '.validate' do
    it 'accepts a well-formed task payload' do
      payload = {
        'id' => 'TASK-0001', 'title' => 't', 'workflow' => { 'key' => 'feature' },
        'kind' => 'task', 'parent_id' => nil, 'priority' => 0,
        'created_at' => '2026-06-24T00:00:00Z', 'status' => 'open', 'labels' => ['backend']
      }
      expect(described_class.validate(payload)).to be_ok
    end

    it 'accepts a legacy payload missing status and labels' do
      payload = { 'id' => 'TASK-0001', 'title' => 't', 'priority' => 0 }
      expect(described_class.validate(payload)).to be_ok
    end

    it 'rejects an out-of-enum status' do
      payload = { 'id' => 'TASK-0001', 'status' => 'frozen' }
      result = described_class.validate(payload)
      expect(result).to be_err
      expect(result.code).to eq(:task_schema_invalid)
    end

    it 'rejects non-string labels' do
      payload = { 'id' => 'TASK-0001', 'labels' => [1, 2] }
      expect(described_class.validate(payload)).to be_err
    end

    it 'rejects a non-integer priority' do
      payload = { 'id' => 'TASK-0001', 'priority' => 'high' }
      expect(described_class.validate(payload)).to be_err
    end
  end

  describe '.settable_status?' do
    it 'is true for user-settable statuses' do
      expect(described_class.settable_status?('on_hold')).to be(true)
    end

    it 'is false for unknown statuses' do
      expect(described_class.settable_status?('abandoned')).to be(false)
    end

    it 'is false for archive-owned statuses (set via the archive flow, not set-status)' do
      expect(described_class.settable_status?('archived')).to be(false)
    end
  end
end
