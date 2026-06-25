# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/tasks/api'

RSpec.describe Owl::Tasks::Api, '.add_dependency / .remove_dependency / .dependencies / .ready' do
  def cli(argv, root)
    Owl::Cli::Api.run(argv: argv, stdout: StringIO.new, stderr: StringIO.new, env: {}, cwd: root.to_s)
  end

  def setup_project(root)
    cli(['init', '--root', root.to_s], root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
      id: feature
      kind: task
      artifacts: {}
      steps:
        - id: a
    YAML
  end

  def create_task(root, title: 't')
    cli(['task', 'create', '--workflow', 'feature', '--title', title, '--root', root.to_s, '--json'], root)
  end

  def create_two(root)
    setup_project(root)
    create_task(root, title: 'A')
    create_task(root, title: 'B')
  end

  def task_yaml(root, task_id)
    YAML.safe_load_file("#{root}/tasks/#{task_id}/task.yaml")
  end

  def index_entry(root, task_id)
    YAML.safe_load_file("#{root}/tasks/index.yaml")['tasks'].find { |t| t['id'] == task_id }
  end

  describe 'create + index defaults' do
    it 'writes blocked_by: [] for a new task and carries it into the index' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root)
        expect(task_yaml(root, 'TASK-0001')['blocked_by']).to eq([])
        expect(index_entry(root, 'TASK-0001')['blocked_by']).to eq([])
      end
    end

    it 'reads a legacy task.yaml without blocked_by as [] in the index' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root)
        payload = task_yaml(root, 'TASK-0001')
        payload.delete('blocked_by')
        write("#{root}/tasks/TASK-0001/task.yaml", payload.to_yaml)
        described_class.rebuild_index(root: root)
        expect(index_entry(root, 'TASK-0001')['blocked_by']).to eq([])
      end
    end
  end

  describe '.add_dependency' do
    it 'adds DEP to TASK.blocked_by in task.yaml and index' do
      with_tmp_project do |root|
        create_two(root)
        result = described_class.add_dependency(root: root, task_id: 'TASK-0002', depends_on: 'TASK-0001')
        expect(result).to be_ok
        expect(result.value[:blocked_by]).to eq(['TASK-0001'])
        expect(task_yaml(root, 'TASK-0002')['blocked_by']).to eq(['TASK-0001'])
        expect(index_entry(root, 'TASK-0002')['blocked_by']).to eq(['TASK-0001'])
      end
    end

    it 'is idempotent when the edge already exists' do
      with_tmp_project do |root|
        create_two(root)
        described_class.add_dependency(root: root, task_id: 'TASK-0002', depends_on: 'TASK-0001')
        result = described_class.add_dependency(root: root, task_id: 'TASK-0002', depends_on: 'TASK-0001')
        expect(result).to be_ok
        expect(task_yaml(root, 'TASK-0002')['blocked_by']).to eq(['TASK-0001'])
      end
    end

    it 'rejects a self-dependency with :self_dependency' do
      with_tmp_project do |root|
        create_two(root)
        result = described_class.add_dependency(root: root, task_id: 'TASK-0001', depends_on: 'TASK-0001')
        expect(result).to be_err
        expect(result.code).to eq(:self_dependency)
      end
    end

    it 'rejects an unknown TASK with :task_not_found' do
      with_tmp_project do |root|
        create_two(root)
        result = described_class.add_dependency(root: root, task_id: 'TASK-9999', depends_on: 'TASK-0001')
        expect(result).to be_err
        expect(result.code).to eq(:task_not_found)
      end
    end

    it 'rejects an unknown DEP with :task_not_found' do
      with_tmp_project do |root|
        create_two(root)
        result = described_class.add_dependency(root: root, task_id: 'TASK-0001', depends_on: 'TASK-9999')
        expect(result).to be_err
        expect(result.code).to eq(:task_not_found)
      end
    end

    it 'rejects a direct cycle with :dependency_cycle carrying the path' do
      with_tmp_project do |root|
        create_two(root)
        described_class.add_dependency(root: root, task_id: 'TASK-0002', depends_on: 'TASK-0001')
        result = described_class.add_dependency(root: root, task_id: 'TASK-0001', depends_on: 'TASK-0002')
        expect(result).to be_err
        expect(result.code).to eq(:dependency_cycle)
        expect(result.details[:cycle].first).to eq(result.details[:cycle].last)
        expect(task_yaml(root, 'TASK-0001')['blocked_by']).to eq([])
      end
    end

    it 'rejects a transitive cycle' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root, title: 'A')
        create_task(root, title: 'B')
        create_task(root, title: 'C')
        described_class.add_dependency(root: root, task_id: 'TASK-0002', depends_on: 'TASK-0001') # B -> A
        described_class.add_dependency(root: root, task_id: 'TASK-0003', depends_on: 'TASK-0002') # C -> B
        result = described_class.add_dependency(root: root, task_id: 'TASK-0001', depends_on: 'TASK-0003') # A -> C
        expect(result).to be_err
        expect(result.code).to eq(:dependency_cycle)
      end
    end
  end

  describe '.remove_dependency' do
    it 'removes an existing edge' do
      with_tmp_project do |root|
        create_two(root)
        described_class.add_dependency(root: root, task_id: 'TASK-0002', depends_on: 'TASK-0001')
        result = described_class.remove_dependency(root: root, task_id: 'TASK-0002', depends_on: 'TASK-0001')
        expect(result).to be_ok
        expect(result.value[:blocked_by]).to eq([])
        expect(task_yaml(root, 'TASK-0002')['blocked_by']).to eq([])
      end
    end

    it 'is a clean no-op for an absent edge' do
      with_tmp_project do |root|
        create_two(root)
        result = described_class.remove_dependency(root: root, task_id: 'TASK-0002', depends_on: 'TASK-0001')
        expect(result).to be_ok
        expect(result.value[:blocked_by]).to eq([])
      end
    end

    it 'returns :task_not_found for an unknown TASK' do
      with_tmp_project do |root|
        create_two(root)
        result = described_class.remove_dependency(root: root, task_id: 'TASK-9999', depends_on: 'TASK-0001')
        expect(result).to be_err
        expect(result.code).to eq(:task_not_found)
      end
    end
  end

  describe '.dependencies' do
    it 'returns blocked_by and computed blocks (reverse scan)' do
      with_tmp_project do |root|
        create_two(root)
        described_class.add_dependency(root: root, task_id: 'TASK-0002', depends_on: 'TASK-0001')
        b = described_class.dependencies(root: root, task_id: 'TASK-0002')
        expect(b.value[:blocked_by]).to eq(['TASK-0001'])
        expect(b.value[:blocks]).to eq([])
        a = described_class.dependencies(root: root, task_id: 'TASK-0001')
        expect(a.value[:blocked_by]).to eq([])
        expect(a.value[:blocks]).to eq(['TASK-0002'])
      end
    end

    it 'returns :task_not_found for an unknown TASK' do
      with_tmp_project do |root|
        create_two(root)
        result = described_class.dependencies(root: root, task_id: 'TASK-9999')
        expect(result).to be_err
        expect(result.code).to eq(:task_not_found)
      end
    end
  end

  describe '.ready' do
    it 'excludes a task while its dependency is unfinished' do
      with_tmp_project do |root|
        create_two(root)
        described_class.add_dependency(root: root, task_id: 'TASK-0002', depends_on: 'TASK-0001')
        ids = described_class.ready(root: root).value[:ready].map { |e| e['id'] }
        expect(ids).to include('TASK-0001')
        expect(ids).not_to include('TASK-0002')
      end
    end

    it 'includes the task once its dependency reaches a terminal status (done)' do
      with_tmp_project do |root|
        create_two(root)
        described_class.add_dependency(root: root, task_id: 'TASK-0002', depends_on: 'TASK-0001')
        described_class.set_status(root: root, task_id: 'TASK-0001', status: 'done')
        ids = described_class.ready(root: root).value[:ready].map { |e| e['id'] }
        expect(ids).to include('TASK-0002')
        expect(ids).not_to include('TASK-0001') # done is terminal for its own readiness
      end
    end

    it 'treats an archived dependency as complete' do
      with_tmp_project do |root|
        create_two(root)
        described_class.add_dependency(root: root, task_id: 'TASK-0002', depends_on: 'TASK-0001')
        # Simulate an archived dependency that still carries an index entry.
        payload = task_yaml(root, 'TASK-0001')
        payload['status'] = 'archived'
        write("#{root}/tasks/TASK-0001/task.yaml", payload.to_yaml)
        described_class.rebuild_index(root: root)
        ids = described_class.ready(root: root).value[:ready].map { |e| e['id'] }
        expect(ids).to include('TASK-0002')
      end
    end

    it 'treats a missing dependency as complete and never crashes' do
      with_tmp_project do |root|
        create_two(root)
        payload = task_yaml(root, 'TASK-0002')
        payload['blocked_by'] = ['TASK-9999']
        write("#{root}/tasks/TASK-0002/task.yaml", payload.to_yaml)
        described_class.rebuild_index(root: root)
        result = described_class.ready(root: root)
        expect(result).to be_ok
        expect(result.value[:ready].map { |e| e['id'] }).to include('TASK-0002')
      end
    end

    it 'excludes a claimed task' do
      with_tmp_project do |root|
        create_two(root)
        described_class.claim(root: root, task_id: 'TASK-0001')
        ids = described_class.ready(root: root).value[:ready].map { |e| e['id'] }
        expect(ids).not_to include('TASK-0001')
      end
    end

    it 'excludes a task whose own status is on_hold' do
      with_tmp_project do |root|
        create_two(root)
        described_class.set_status(root: root, task_id: 'TASK-0001', status: 'on_hold')
        ids = described_class.ready(root: root).value[:ready].map { |e| e['id'] }
        expect(ids).not_to include('TASK-0001')
        expect(ids).to include('TASK-0002')
      end
    end

    it 'excludes a task whose own status is blocked' do
      with_tmp_project do |root|
        create_two(root)
        described_class.set_status(root: root, task_id: 'TASK-0001', status: 'blocked')
        ids = described_class.ready(root: root).value[:ready].map { |e| e['id'] }
        expect(ids).not_to include('TASK-0001')
        expect(ids).to include('TASK-0002')
      end
    end

    it 'keeps priority/age sort order when filtering' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root, title: 'low')
        create_task(root, title: 'high')
        described_class.set_priority(root: root, task_id: 'TASK-0002', priority: 5)
        ids = described_class.ready(root: root).value[:ready].map { |e| e['id'] }
        expect(ids).to eq(%w[TASK-0002 TASK-0001])
      end
    end
  end

  describe '.delete dangling-ref cleanup' do
    it 'strips the deleted id from other tasks blocked_by (no crash on ready)' do
      with_tmp_project do |root|
        create_two(root)
        described_class.add_dependency(root: root, task_id: 'TASK-0002', depends_on: 'TASK-0001')
        described_class.delete(root: root, task_id: 'TASK-0001')
        expect(task_yaml(root, 'TASK-0002')['blocked_by']).to eq([])
        expect(index_entry(root, 'TASK-0002')['blocked_by']).to eq([])
        result = described_class.ready(root: root)
        expect(result).to be_ok
        expect(result.value[:ready].map { |e| e['id'] }).to include('TASK-0002')
      end
    end
  end
end
