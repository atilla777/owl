# frozen_string_literal: true

require 'pathname'
require 'tmpdir'

require 'owl/tasks/internal/task_reader'

RSpec.describe Owl::Tasks::Internal::TaskReader do
  around do |example|
    Dir.mktmpdir do |dir|
      @tasks_root = Pathname.new(dir)
      example.run
    end
  end

  attr_reader :tasks_root

  def write_task(dir, id:, extra: {})
    dir.mkpath
    payload = { 'id' => id, 'title' => 't', 'steps' => [] }.merge(extra)
    (dir + 'task.yaml').write(payload.to_yaml)
  end

  describe '.read' do
    it 'reads a live task from tasks/<id>/' do
      write_task(tasks_root + 'TASK-0001', id: 'TASK-0001')
      result = described_class.read(tasks_root: tasks_root, task_id: 'TASK-0001')
      expect(result).to be_ok
      expect(result.value[:payload]['id']).to eq('TASK-0001')
    end

    it 'falls back to the archived location under tasks/archive/' do
      write_task(tasks_root + 'archive' + '2026-05-17-TASK-0001-some-slug',
                 id: 'TASK-0001', extra: { 'status' => 'archived' })
      result = described_class.read(tasks_root: tasks_root, task_id: 'TASK-0001')
      expect(result).to be_ok
      expect(result.value[:payload]).to include('status' => 'archived')
      expect(result.value[:path]).to include('archive/2026-05-17-TASK-0001-some-slug')
    end

    it 'prefers the live task when both live and archived copies exist' do
      write_task(tasks_root + 'TASK-0001', id: 'TASK-0001', extra: { 'status' => 'open' })
      write_task(tasks_root + 'archive' + '2026-05-17-TASK-0001-slug',
                 id: 'TASK-0001', extra: { 'status' => 'archived' })
      result = described_class.read(tasks_root: tasks_root, task_id: 'TASK-0001')
      expect(result.value[:payload]).to include('status' => 'open')
    end

    it 'does not confuse TASK-1 with TASK-10 (boundary-anchored match)' do
      write_task(tasks_root + 'archive' + '2026-05-17-TASK-10-ten',
                 id: 'TASK-10', extra: { 'status' => 'archived' })
      result = described_class.read(tasks_root: tasks_root, task_id: 'TASK-1')
      expect(result).to be_err
      expect(result.code).to eq(:task_not_found)
    end

    it 'confirms by the id field, ignoring a slug that merely contains the id' do
      # Directory name slug contains "TASK-0001" as text, but the task is TASK-0002.
      write_task(tasks_root + 'archive' + '2026-05-17-TASK-0002-fixes-TASK-0001',
                 id: 'TASK-0002', extra: { 'status' => 'archived' })
      expect(described_class.read(tasks_root: tasks_root, task_id: 'TASK-0001')).to be_err
      expect(described_class.read(tasks_root: tasks_root, task_id: 'TASK-0002')).to be_ok
    end

    it 'returns task_not_found (live path) when the task exists nowhere' do
      result = described_class.read(tasks_root: tasks_root, task_id: 'TASK-9999')
      expect(result).to be_err
      expect(result.code).to eq(:task_not_found)
    end
  end

  describe '.task_yaml_path' do
    it 'returns the live path for a non-existent task (so creation is unaffected)' do
      path = described_class.task_yaml_path(tasks_root: tasks_root, task_id: 'TASK-0003')
      expect(path.to_s).to eq((tasks_root + 'TASK-0003' + 'task.yaml').to_s)
    end

    it 'returns the archived path once the task has been archived' do
      write_task(tasks_root + 'archive' + '2026-05-17-TASK-0004-slug', id: 'TASK-0004')
      path = described_class.task_yaml_path(tasks_root: tasks_root, task_id: 'TASK-0004')
      expect(path.to_s).to include('archive/2026-05-17-TASK-0004-slug')
    end
  end
end
