# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/tasks/api'

RSpec.describe Owl::Tasks::Api, '.set_status / .add_label / .remove_label / .query' do
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

  def task_yaml(root, task_id)
    YAML.safe_load_file("#{root}/tasks/#{task_id}/task.yaml")
  end

  def index_entry(root, task_id)
    YAML.safe_load_file("#{root}/tasks/index.yaml")['tasks'].find { |t| t['id'] == task_id }
  end

  describe 'create defaults' do
    it 'writes status: open and labels: [] for a new task' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root)
        payload = task_yaml(root, 'TASK-0001')
        expect(payload['status']).to eq('open')
        expect(payload['labels']).to eq([])
      end
    end

    it 'carries status and labels into the index entry' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root)
        entry = index_entry(root, 'TASK-0001')
        expect(entry['status']).to eq('open')
        expect(entry['labels']).to eq([])
      end
    end
  end

  describe '.set_status' do
    it 'updates the explicit task-level status' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root)
        result = described_class.set_status(root: root, task_id: 'TASK-0001', status: 'on_hold')
        expect(result).to be_ok
        expect(result.value[:status]).to eq('on_hold')
        expect(task_yaml(root, 'TASK-0001')['status']).to eq('on_hold')
        expect(index_entry(root, 'TASK-0001')['status']).to eq('on_hold')
      end
    end

    it 'rejects a status outside the settable enum with :invalid_status' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root)
        result = described_class.set_status(root: root, task_id: 'TASK-0001', status: 'bogus')
        expect(result).to be_err
        expect(result.code).to eq(:invalid_status)
        # disk is untouched
        expect(task_yaml(root, 'TASK-0001')['status']).to eq('open')
      end
    end

    it 'returns task_not_found for an unknown task' do
      with_tmp_project do |root|
        setup_project(root)
        result = described_class.set_status(root: root, task_id: 'TASK-9999', status: 'done')
        expect(result).to be_err
        expect(result.code).to eq(:task_not_found)
      end
    end

    it 'rejects a payload that violates the schema with :task_schema_invalid' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root)
        payload = task_yaml(root, 'TASK-0001')
        payload['priority'] = 'high' # invalid: schema requires integer
        File.write("#{root}/tasks/TASK-0001/task.yaml", YAML.dump(payload))

        result = described_class.set_status(root: root, task_id: 'TASK-0001', status: 'done')
        expect(result).to be_err
        expect(result.code).to eq(:task_schema_invalid)
      end
    end
  end

  describe '.add_label / .remove_label' do
    it 'adds a label idempotently without duplicates' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root)
        described_class.add_label(root: root, task_id: 'TASK-0001', label: 'backend')
        result = described_class.add_label(root: root, task_id: 'TASK-0001', label: '  backend  ')
        expect(result).to be_ok
        expect(result.value[:labels]).to eq(['backend'])
        expect(index_entry(root, 'TASK-0001')['labels']).to eq(['backend'])
      end
    end

    it 'removes a present label and refreshes the index' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root)
        described_class.add_label(root: root, task_id: 'TASK-0001', label: 'backend')
        described_class.add_label(root: root, task_id: 'TASK-0001', label: 'urgent')
        result = described_class.remove_label(root: root, task_id: 'TASK-0001', label: 'backend')
        expect(result).to be_ok
        expect(result.value[:labels]).to eq(['urgent'])
        expect(index_entry(root, 'TASK-0001')['labels']).to eq(['urgent'])
      end
    end

    it 'treats removal of an absent label as a clean no-op' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root)
        result = described_class.remove_label(root: root, task_id: 'TASK-0001', label: 'ghost')
        expect(result).to be_ok
        expect(result.value[:labels]).to eq([])
      end
    end

    it 'returns task_not_found for an unknown task' do
      with_tmp_project do |root|
        setup_project(root)
        result = described_class.add_label(root: root, task_id: 'TASK-9999', label: 'x')
        expect(result).to be_err
        expect(result.code).to eq(:task_not_found)
      end
    end
  end

  describe '.query' do
    def seed_three(root)
      setup_project(root)
      create_task(root, title: 'one')   # TASK-0001
      create_task(root, title: 'two')   # TASK-0002
      create_task(root, title: 'three') # TASK-0003
      described_class.set_status(root: root, task_id: 'TASK-0001', status: 'on_hold')
      described_class.add_label(root: root, task_id: 'TASK-0001', label: 'backend')
      described_class.add_label(root: root, task_id: 'TASK-0002', label: 'backend')
      cli(['task', 'set-priority', 'TASK-0003', '5', '--root', root.to_s, '--json'], root)
    end

    it 'filters by status' do
      with_tmp_project do |root|
        seed_three(root)
        ids = described_class.query(root: root, filters: { status: 'on_hold' }).value[:tasks].map { |t| t['id'] }
        expect(ids).to eq(['TASK-0001'])
      end
    end

    it 'combines status AND label (intersection only)' do
      with_tmp_project do |root|
        seed_three(root)
        result = described_class.query(root: root, filters: { status: 'on_hold', label: 'backend' })
        expect(result.value[:tasks].map { |t| t['id'] }).to eq(['TASK-0001'])

        # status open + label backend -> only TASK-0002 (TASK-0001 is on_hold)
        open_backend = described_class.query(root: root, filters: { status: 'open', label: 'backend' })
        expect(open_backend.value[:tasks].map { |t| t['id'] }).to eq(['TASK-0002'])
      end
    end

    it 'filters by priority' do
      with_tmp_project do |root|
        seed_three(root)
        ids = described_class.query(root: root, filters: { priority: 5 }).value[:tasks].map { |t| t['id'] }
        expect(ids).to eq(['TASK-0003'])
      end
    end

    it 'filters by workflow and returns all when matched' do
      with_tmp_project do |root|
        seed_three(root)
        ids = described_class.query(root: root, filters: { workflow: 'feature' }).value[:tasks].map { |t| t['id'] }
        expect(ids).to contain_exactly('TASK-0001', 'TASK-0002', 'TASK-0003')
      end
    end

    it 'filters by parent_id' do
      with_tmp_project do |root|
        seed_three(root)
        ids = described_class.query(root: root, filters: { parent: 'TASK-0099' }).value[:tasks]
        expect(ids).to eq([])
      end
    end

    it 'returns the full roster with no filters' do
      with_tmp_project do |root|
        seed_three(root)
        result = described_class.query(root: root, filters: {})
        expect(result.value[:tasks].size).to eq(3)
      end
    end
  end

  describe 'archive sets status: archived' do
    it 'writes status: archived into the relocated task.yaml' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root)
        # Mark the single step done so the completion gate allows archive.
        payload = task_yaml(root, 'TASK-0001')
        payload['steps'].each { |s| s['status'] = 'done' }
        File.write("#{root}/tasks/TASK-0001/task.yaml", YAML.dump(payload))

        result = described_class.archive(root: root, task_id: 'TASK-0001')
        expect(result).to be_ok
        archived = YAML.safe_load_file(File.join(result.value[:to], 'task.yaml'))
        expect(archived['status']).to eq('archived')
      end
    end
  end

  describe 'legacy task.yaml (no status / labels)' do
    it 'reads as status: open, labels: [] in the rebuilt index' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root)
        # Simulate a pre-tracker task.yaml by stripping the new fields.
        payload = task_yaml(root, 'TASK-0001')
        payload.delete('status')
        payload.delete('labels')
        File.write("#{root}/tasks/TASK-0001/task.yaml", YAML.dump(payload))

        cli(['task', 'index', 'rebuild', '--root', root.to_s, '--json'], root)
        entry = index_entry(root, 'TASK-0001')
        expect(entry['status']).to eq('open')
        expect(entry['labels']).to eq([])
      end
    end
  end
end
