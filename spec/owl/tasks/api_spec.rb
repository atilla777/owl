# frozen_string_literal: true

require 'json'
require 'yaml'

require 'owl/tasks/api'
require 'owl/steps/api'
require 'owl/config/api'
require 'owl/cli/internal/commands/init'

RSpec.describe Owl::Tasks::Api do
  def init_project(root)
    Owl::Cli::Internal::Commands::Init.run(
      argv: ['--root', root.to_s],
      stdout: StringIO.new,
      stderr: StringIO.new,
      cwd: root.to_s,
      env: {}
    )
  end

  def seed_feature_workflow(root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
          version: "1.0"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
      id: feature
      kind: feature
      title: Feature workflow
      description: "Stub feature workflow"
      steps:
        - id: noop
          kind: noop
      artifacts: []
    YAML
  end

  def seed_composite_and_feature_workflows(root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        composite_feature:
          enabled: true
          source: "workflows/composite_feature/workflow.yaml"
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/composite_feature/workflow.yaml", <<~YAML)
      id: composite_feature
      kind: composite_task
      steps:
        - id: brief
          kind: noop
      artifacts:
        brief:
          type: brief
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
      id: feature
      kind: feature
      steps:
        - id: noop
          kind: noop
    YAML
  end

  describe '.create' do
    it 'returns project_root_not_found when .owl/config.yaml is missing' do
      with_tmp_project do |root|
        result = described_class.create(root: root, workflow: 'feature', title: 'X')
        expect(result).to be_err
        expect(result.code).to eq(:config_missing)
      end
    end

    it 'returns unknown_workflow when the workflow key is not in the registry' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.create(root: root, workflow: 'nope', title: 'X')
        expect(result).to be_err
        expect(result.code).to eq(:unknown_workflow)
      end
    end

    it 'writes tasks/TASK-0001/task.yaml on happy path' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)

        result = described_class.create(root: root, workflow: 'feature', title: 'first task')
        expect(result).to be_ok
        expect(result.value[:task_id]).to eq('TASK-0001')

        task_yaml = YAML.safe_load(Pathname.new("#{root}/tasks/TASK-0001/task.yaml").read)
        expect(task_yaml).to include(
          'id' => 'TASK-0001',
          'title' => 'first task',
          'kind' => 'feature',
          'artifacts' => [],
          'parent_id' => nil
        )
        expect(task_yaml['workflow']).to include('key' => 'feature', 'version' => '1.0')
        expect(task_yaml['steps'].first['id']).to eq('noop')
        expect(task_yaml['created_at']).to match(/\A\d{4}-\d{2}-\d{2}T/)
      end
    end

    it 'updates tasks/index.yaml after happy path create' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'first task')

        index = YAML.safe_load(Pathname.new("#{root}/tasks/index.yaml").read)
        expect(index['tasks'].map { |e| e['id'] }).to eq(['TASK-0001'])
      end
    end

    it 'allocates sequential TASK ids' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)

        first = described_class.create(root: root, workflow: 'feature', title: 'first')
        second = described_class.create(root: root, workflow: 'feature', title: 'second')

        expect(first.value[:task_id]).to eq('TASK-0001')
        expect(second.value[:task_id]).to eq('TASK-0002')
      end
    end

    it 'treats workflows without explicit steps/artifacts as empty' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/.owl/workflows.yaml", <<~YAML)
          schema_version: 1
          workflows:
            empty:
              source: "workflows/empty.yaml"
        YAML
        write("#{root}/.owl/workflows/empty.yaml", "id: empty\nkind: noop\n")

        result = described_class.create(root: root, workflow: 'empty', title: 'e')
        expect(result).to be_ok
        task_yaml = YAML.safe_load(Pathname.new("#{root}/tasks/TASK-0001/task.yaml").read)
        expect(task_yaml['steps']).to eq([])
        expect(task_yaml['artifacts']).to eq([])
        expect(task_yaml['kind']).to eq('noop')
      end
    end

    it 'lets the caller override kind explicitly' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        result = described_class.create(root: root, workflow: 'feature', title: 't', kind: 'custom_kind',
                                        parent_id: 'TASK-0042')
        expect(result).to be_ok
        task_yaml = YAML.safe_load(Pathname.new("#{root}/tasks/TASK-0001/task.yaml").read)
        expect(task_yaml['kind']).to eq('custom_kind')
        expect(task_yaml['parent_id']).to eq('TASK-0042')
      end
    end
  end

  describe '.list' do
    it 'returns empty list on a fresh project' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.list(root: root)
        expect(result).to be_ok
        expect(result.value[:tasks]).to eq([])
        expect(result.value[:schema_version]).to eq(1)
      end
    end

    it 'returns both tasks after two creates' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'first')
        described_class.create(root: root, workflow: 'feature', title: 'second')
        result = described_class.list(root: root)
        expect(result.value[:tasks].map { |t| t['task_id'] }).to eq(%w[TASK-0001 TASK-0002])
        expect(result.value[:tasks].first).not_to have_key('id')
      end
    end

    it 'returns index_yaml_invalid when index.yaml is not a mapping' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/tasks/index.yaml", "- not\n- a\n- mapping\n")
        result = described_class.list(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:index_yaml_invalid)
      end
    end
  end

  describe '.inspect' do
    it 'returns the full task payload when present' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'first')
        result = described_class.inspect(root: root, task_id: 'TASK-0001')
        expect(result).to be_ok
        expect(result.value[:payload]['title']).to eq('first')
      end
    end

    it 'returns task_not_found when the task directory does not exist' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.inspect(root: root, task_id: 'TASK-9999')
        expect(result).to be_err
        expect(result.code).to eq(:task_not_found)
      end
    end

    it 'returns task_yaml_invalid when task.yaml is not a mapping' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/tasks/TASK-0007/task.yaml", "- broken\n")
        result = described_class.inspect(root: root, task_id: 'TASK-0007')
        expect(result).to be_err
        expect(result.code).to eq(:task_yaml_invalid)
      end
    end
  end

  describe '.use and .current' do
    it 'writes and reads back the current task pointer' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'first')

        use_result = described_class.use(root: root, task_id: 'TASK-0001')
        expect(use_result).to be_ok
        expect(use_result.value[:task_id]).to eq('TASK-0001')
        expect(Pathname.new("#{root}/.owl/local/current.yaml").exist?).to be(true)

        current_result = described_class.current(root: root)
        expect(current_result).to be_ok
        expect(current_result.value[:task_id]).to eq('TASK-0001')
        expect(current_result.value[:payload]['title']).to eq('first')
      end
    end

    it 'use fails with task_not_found for an unknown task id' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.use(root: root, task_id: 'TASK-9999')
        expect(result).to be_err
        expect(result.code).to eq(:task_not_found)
      end
    end

    it 'current returns no_current_task when no pointer file exists' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.current(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:no_current_task)
      end
    end

    it 'current returns no_current_task when the pointer references a missing task' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/.owl/local/current.yaml", "task_id: TASK-9999\nset_at: '2026-05-17T00:00:00Z'\n")
        result = described_class.current(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:task_not_found)
      end
    end

    it 'current returns no_current_task when the pointer file is malformed' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/.owl/local/current.yaml", "- broken\n")
        result = described_class.current(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:no_current_task)
      end
    end
  end

  describe '.rebuild_index' do
    it 'reflects manual title edits in task.yaml' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'first')

        task_yaml_path = Pathname.new("#{root}/tasks/TASK-0001/task.yaml")
        edited = YAML.safe_load(task_yaml_path.read)
        edited['title'] = 'edited'
        task_yaml_path.write(YAML.dump(edited))

        result = described_class.rebuild_index(root: root)
        expect(result).to be_ok
        index = YAML.safe_load(Pathname.new("#{root}/tasks/index.yaml").read)
        expect(index['tasks'].first['title']).to eq('edited')
      end
    end

    it 'reports broken task.yaml files in errors[] but keeps valid entries' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'first')

        write("#{root}/tasks/TASK-0005/task.yaml", "- broken\n")
        write("#{root}/tasks/TASK-0006/task.yaml", ":\n  : broken")

        result = described_class.rebuild_index(root: root)
        expect(result).to be_ok
        codes = result.value[:errors].map { |e| e[:code] }
        expect(codes).to include(:task_yaml_invalid)
        ids = result.value[:tasks].map { |t| t['id'] }
        expect(ids).to include('TASK-0001')
      end
    end

    it 'reports missing task.yaml inside a TASK-* directory' do
      with_tmp_project do |root|
        init_project(root)
        FileUtils.mkdir_p("#{root}/tasks/TASK-0011")
        result = described_class.rebuild_index(root: root)
        expect(result).to be_ok
        codes = result.value[:errors].map { |e| e[:code] }
        expect(codes).to include(:task_yaml_missing)
      end
    end
  end

  describe 'id generator' do
    it 'continues numbering past the highest TASK-* directory even if index is empty' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        FileUtils.mkdir_p("#{root}/tasks/TASK-0042")
        write("#{root}/tasks/TASK-0042/task.yaml", "id: TASK-0042\ntitle: stub\n")

        result = described_class.create(root: root, workflow: 'feature', title: 'after')
        expect(result.value[:task_id]).to eq('TASK-0043')
      end
    end
  end

  describe 'backend resolution via Owl::Internal::BackendResolver' do
    it 'returns Result.err(:unknown_backend) from .create when backend is unrecognised' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        write("#{root}/.owl/config.yaml",
              File.read("#{root}/.owl/config.yaml") + "settings:\n  storage:\n    backend: imaginary\n")

        result = described_class.create(root: root, workflow: 'feature', title: 'doomed')
        expect(result).to be_a(Owl::Result::Err)
        expect(result.code).to eq(:unknown_backend)
        expect(result.message).to include('tasks')
        expect(result.message).to include('imaginary')
        expect(result.details).to include(scope: :tasks, backend_name: 'imaginary')
      end
    end
  end

  describe 'public DTO is free of filesystem path keys' do
    it '.list omits index_path / task_path / local from the Ok payload' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.list(root: root)
        expect(result).to be_ok
        expect(result.value.keys).not_to include(:index_path, :task_path, :local, :path)
        expect(result.value.keys).to contain_exactly(:schema_version, :tasks)
      end
    end

    it '.create omits task_path / index_path / local from the Ok payload' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        result = described_class.create(root: root, workflow: 'feature', title: 'x')
        expect(result).to be_ok
        expect(result.value.keys).not_to include(:task_path, :index_path, :local, :path)
      end
    end

    it '.inspect omits path / local from the Ok payload' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'x')
        result = described_class.inspect(root: root, task_id: 'TASK-0001')
        expect(result).to be_ok
        expect(result.value.keys).not_to include(:path, :local, :task_path)
      end
    end

    it '.current omits pointer_path / task_path / local from the Ok payload' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'x')
        described_class.use(root: root, task_id: 'TASK-0001')
        result = described_class.current(root: root)
        expect(result).to be_ok
        expect(result.value.keys).not_to include(:pointer_path, :task_path, :local, :path)
      end
    end

    it '.use omits path / local from the Ok payload' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'x')
        result = described_class.use(root: root, task_id: 'TASK-0001')
        expect(result).to be_ok
        expect(result.value.keys).not_to include(:path, :local, :pointer_path)
      end
    end

    it '.rebuild_index omits index_path / local from the Ok payload' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.rebuild_index(root: root)
        expect(result).to be_ok
        expect(result.value.keys).not_to include(:index_path, :local)
      end
    end

    it '.child_create omits task_path / index_path / local from the Ok payload' do
      with_tmp_project do |root|
        init_project(root)
        seed_composite_and_feature_workflows(root)
        parent = described_class.create(root: root, workflow: 'composite_feature', title: 'p')
        result = described_class.child_create(
          root: root, parent_id: parent.value[:task_id], workflow: 'feature', title: 'c'
        )
        expect(result).to be_ok
        expect(result.value.keys).not_to include(:task_path, :index_path, :local, :path)
      end
    end
  end

  describe '.local_paths' do
    it 'without task_id returns Ok with Local::Index and Local::Pointer' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.local_paths(root: root)
        expect(result).to be_ok
        expect(result.value[:index]).to be_a(Owl::Tasks::Local::Index)
        expect(result.value[:index].index_path).to eq("#{root}/tasks/index.yaml")
        expect(result.value[:pointer]).to be_a(Owl::Tasks::Local::Pointer)
        expect(result.value[:pointer].pointer_path).to eq("#{root}/.owl/local/current.yaml")
      end
    end

    it 'with task_id returns Ok with Local::TaskFile + Local::Index + Local::Pointer' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.local_paths(root: root, task_id: 'TASK-0001')
        expect(result).to be_ok
        expect(result.value[:task_file]).to be_a(Owl::Tasks::Local::TaskFile)
        expect(result.value[:task_file].task_path).to eq("#{root}/tasks/TASK-0001/task.yaml")
        expect(result.value[:index]).to be_a(Owl::Tasks::Local::Index)
        expect(result.value[:pointer]).to be_a(Owl::Tasks::Local::Pointer)
      end
    end

    it 'propagates backend resolution errors' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/.owl/config.yaml",
              File.read("#{root}/.owl/config.yaml") + "settings:\n  storage:\n    backend: imaginary\n")
        result = described_class.local_paths(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:unknown_backend)
      end
    end

    it 'returns Err(:no_local_view) when backend has no local view' do
      stub_backend = Class.new do
        def self.name
          'StubBackend'
        end
      end.new
      allow(Owl::Internal::BackendResolver).to receive(:resolve)
        .with(root: '/anywhere', scope: :tasks)
        .and_return(Owl::Result.ok(stub_backend))

      result = described_class.local_paths(root: '/anywhere')
      expect(result).to be_err
      expect(result.code).to eq(:no_local_view)
      expect(result.details[:backend]).to eq('StubBackend')
    end

    it 'propagates Paths.resolve errors when project root is missing' do
      with_tmp_project do |root|
        # No init_project — no .owl/config.yaml
        result = described_class.local_paths(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:config_missing)
      end
    end
  end

  describe 'priority' do
    it 'defaults to 0 on create' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'p')
        task_yaml = YAML.safe_load(Pathname.new("#{root}/tasks/TASK-0001/task.yaml").read)
        expect(task_yaml['priority']).to eq(0)
      end
    end

    it 'records an explicit priority on create' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'p', priority: 7)
        task_yaml = YAML.safe_load(Pathname.new("#{root}/tasks/TASK-0001/task.yaml").read)
        expect(task_yaml['priority']).to eq(7)
      end
    end

    it 'surfaces priority in the index after create' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'p', priority: 3)
        index = YAML.safe_load(Pathname.new("#{root}/tasks/index.yaml").read)
        expect(index['tasks'].first['priority']).to eq(3)
      end
    end
  end

  describe '.set_priority' do
    it 'updates the task priority and reindexes' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'p')
        result = described_class.set_priority(root: root, task_id: 'TASK-0001', priority: 9)
        expect(result).to be_ok
        expect(result.value[:priority]).to eq(9)
        index = YAML.safe_load(Pathname.new("#{root}/tasks/index.yaml").read)
        expect(index['tasks'].first['priority']).to eq(9)
      end
    end

    it 'accepts a numeric string priority' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'p')
        result = described_class.set_priority(root: root, task_id: 'TASK-0001', priority: '4')
        expect(result).to be_ok
        expect(result.value[:priority]).to eq(4)
      end
    end

    it 'returns invalid_priority for a non-integer' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'p')
        result = described_class.set_priority(root: root, task_id: 'TASK-0001', priority: 'abc')
        expect(result).to be_err
        expect(result.code).to eq(:invalid_priority)
      end
    end

    it 'propagates task_not_found for an unknown task' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.set_priority(root: root, task_id: 'TASK-9999', priority: 1)
        expect(result).to be_err
        expect(result.code).to eq(:task_not_found)
      end
    end
  end

  describe '.claim / .release / .claims' do
    def seed_one(root)
      init_project(root)
      seed_feature_workflow(root)
      described_class.create(root: root, workflow: 'feature', title: 'c')
    end

    it 'claims an explicit task and writes the current pointer' do
      with_tmp_project do |root|
        seed_one(root)
        result = described_class.claim(root: root, task_id: 'TASK-0001')
        expect(result).to be_ok
        expect(result.value[:task_id]).to eq('TASK-0001')
        expect(result.value[:token]).to be_a(String)
        expect(result.value[:ready_step_ids]).to eq(['noop'])
        expect(Pathname.new("#{root}/.owl/local/claims/TASK-0001.yaml").exist?).to be(true)
        expect(Pathname.new("#{root}/.owl/local/current.yaml").exist?).to be(true)
      end
    end

    it 'auto-selects the highest-priority task with --next' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'low')
        described_class.create(root: root, workflow: 'feature', title: 'high', priority: 5)
        result = described_class.claim(root: root, next_: true)
        expect(result).to be_ok
        expect(result.value[:task_id]).to eq('TASK-0002')
      end
    end

    it 'returns no_available_task when --next finds nothing runnable' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.claim(root: root, next_: true)
        expect(result).to be_err
        expect(result.code).to eq(:no_available_task)
      end
    end

    it 'returns invalid_arguments when neither task_id nor --next is given' do
      with_tmp_project do |root|
        seed_one(root)
        result = described_class.claim(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:invalid_arguments)
      end
    end

    it 'returns lease_held when claiming an already-claimed task' do
      with_tmp_project do |root|
        seed_one(root)
        described_class.claim(root: root, task_id: 'TASK-0001')
        result = described_class.claim(root: root, task_id: 'TASK-0001')
        expect(result).to be_err
        expect(result.code).to eq(:lease_held)
      end
    end

    it 'skips a live claim and picks the next candidate with --next' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'one')
        described_class.create(root: root, workflow: 'feature', title: 'two')
        described_class.claim(root: root, task_id: 'TASK-0001')
        result = described_class.claim(root: root, next_: true)
        expect(result).to be_ok
        expect(result.value[:task_id]).to eq('TASK-0002')
      end
    end

    it 'does not auto-claim a dep-blocked task with --next' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'dep')
        described_class.create(root: root, workflow: 'feature', title: 'blocked', priority: 5)
        described_class.add_dependency(root: root, task_id: 'TASK-0002', depends_on: 'TASK-0001')
        result = described_class.claim(root: root, next_: true)
        expect(result).to be_ok
        expect(result.value[:task_id]).to eq('TASK-0001')
      end
    end

    it 'does not auto-claim an on_hold task with --next' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'parked', priority: 5)
        described_class.create(root: root, workflow: 'feature', title: 'live')
        described_class.set_status(root: root, task_id: 'TASK-0001', status: 'on_hold')
        result = described_class.claim(root: root, next_: true)
        expect(result).to be_ok
        expect(result.value[:task_id]).to eq('TASK-0002')
      end
    end

    it 'steals a live claim with steal: true and reports the displaced holder' do
      with_tmp_project do |root|
        seed_one(root)
        first = described_class.claim(root: root, task_id: 'TASK-0001', label: 'session-A')
        result = described_class.claim(root: root, task_id: 'TASK-0001', steal: true)
        expect(result).to be_ok
        expect(result.value[:token]).not_to eq(first.value[:token])
        expect(result.value[:stole_from])
          .to include(claimed_by: first.value[:token], label: 'session-A', expired: false)
      end
    end

    it 'adds an adopt hint when --steal displaces a task with a running step (TASK-0023 FF3)' do
      with_tmp_project do |root|
        seed_one(root)
        Owl::Steps::Api.start(root: root, task_id: 'TASK-0001', step_id: 'noop')
        result = described_class.claim(root: root, task_id: 'TASK-0001', steal: true)
        expect(result).to be_ok
        expect(result.value[:running_step]).to eq('noop')
        expect(result.value[:hint]).to include('owl task adopt TASK-0001')
        expect(result.value[:hint]).to include("step 'noop' is running")
      end
    end

    it 'omits the adopt hint when --steal hits a task with no running step (TASK-0023 FF3)' do
      with_tmp_project do |root|
        seed_one(root)
        result = described_class.claim(root: root, task_id: 'TASK-0001', steal: true)
        expect(result).to be_ok
        expect(result.value).not_to have_key(:hint)
        expect(result.value).not_to have_key(:running_step)
      end
    end

    it 'leaves stole_from nil for a plain (non-steal) claim' do
      with_tmp_project do |root|
        seed_one(root)
        result = described_class.claim(root: root, task_id: 'TASK-0001')
        expect(result.value[:stole_from]).to be_nil
      end
    end

    it 'releases a held claim with the right token' do
      with_tmp_project do |root|
        seed_one(root)
        claim = described_class.claim(root: root, task_id: 'TASK-0001')
        result = described_class.release(root: root, task_id: 'TASK-0001', token: claim.value[:token])
        expect(result).to be_ok
        expect(result.value[:released]).to be(true)
        expect(Pathname.new("#{root}/.owl/local/claims/TASK-0001.yaml").exist?).to be(false)
      end
    end

    it 'returns lease_not_owned when releasing with the wrong token' do
      with_tmp_project do |root|
        seed_one(root)
        described_class.claim(root: root, task_id: 'TASK-0001')
        result = described_class.release(root: root, task_id: 'TASK-0001', token: 'nope')
        expect(result).to be_err
        expect(result.code).to eq(:lease_not_owned)
      end
    end

    it 'returns lease_not_found when releasing an unclaimed task' do
      with_tmp_project do |root|
        seed_one(root)
        result = described_class.release(root: root, task_id: 'TASK-0001', token: 'x')
        expect(result).to be_err
        expect(result.code).to eq(:lease_not_found)
      end
    end

    it 'lists active claims' do
      with_tmp_project do |root|
        seed_one(root)
        described_class.claim(root: root, task_id: 'TASK-0001')
        result = described_class.claims(root: root)
        expect(result).to be_ok
        expect(result.value[:claims].map { |c| c[:task_id] }).to eq(['TASK-0001'])
        expect(result.value[:claims].first[:expired]).to be(false)
      end
    end
  end

  describe '.heartbeat' do
    def seed_one(root)
      init_project(root)
      seed_feature_workflow(root)
      described_class.create(root: root, workflow: 'feature', title: 'c')
    end

    it 'extends a held lease and rewrites heartbeat_at/expires_at' do
      with_tmp_project do |root|
        seed_one(root)
        claim = described_class.claim(root: root, task_id: 'TASK-0001')
        lease_path = Pathname.new("#{root}/.owl/local/claims/TASK-0001.yaml")
        before = YAML.safe_load(lease_path.read, permitted_classes: [Time])
        result = described_class.heartbeat(root: root, task_id: 'TASK-0001', token: claim.value[:token], ttl: 999)
        expect(result).to be_ok
        expect(result.value[:ttl_seconds]).to eq(999)
        after = YAML.safe_load(lease_path.read, permitted_classes: [Time])
        expect(after['claimed_by']).to eq(before['claimed_by'])
        expect(after['expires_at']).to eq(result.value[:expires_at])
      end
    end

    it 'defaults to the lease\'s own TTL when no --ttl is given' do
      with_tmp_project do |root|
        seed_one(root)
        claim = described_class.claim(root: root, task_id: 'TASK-0001', ttl: 123)
        result = described_class.heartbeat(root: root, task_id: 'TASK-0001', token: claim.value[:token])
        expect(result.value[:ttl_seconds]).to eq(123)
      end
    end

    it 'returns lease_lost (recoverable) when the token does not own the lease' do
      with_tmp_project do |root|
        seed_one(root)
        described_class.claim(root: root, task_id: 'TASK-0001')
        result = described_class.heartbeat(root: root, task_id: 'TASK-0001', token: 'someone-else')
        expect(result).to be_err
        expect(result.code).to eq(:lease_lost)
        expect(result.error_class).to eq(:recoverable)
      end
    end

    it 'returns lease_lost when no lease exists at all' do
      with_tmp_project do |root|
        seed_one(root)
        result = described_class.heartbeat(root: root, task_id: 'TASK-0001', token: 'x')
        expect(result).to be_err
        expect(result.code).to eq(:lease_lost)
      end
    end
  end

  describe '.claim with configurable TTL' do
    it 'honours settings.concurrency.claim_ttl_seconds when no --ttl is passed' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'c')
        Owl::Config::Api.write_key(root: root, key: 'settings.concurrency.claim_ttl_seconds', value: '42')
        described_class.claim(root: root, task_id: 'TASK-0001')
        lease = YAML.safe_load(Pathname.new("#{root}/.owl/local/claims/TASK-0001.yaml").read, permitted_classes: [Time])
        expect(lease['ttl_seconds']).to eq(42)
      end
    end

    it 'lets an explicit ttl override the configured default' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'c')
        Owl::Config::Api.write_key(root: root, key: 'settings.concurrency.claim_ttl_seconds', value: '42')
        described_class.claim(root: root, task_id: 'TASK-0001', ttl: 7)
        lease = YAML.safe_load(Pathname.new("#{root}/.owl/local/claims/TASK-0001.yaml").read, permitted_classes: [Time])
        expect(lease['ttl_seconds']).to eq(7)
      end
    end
  end

  describe '.available' do
    it 'ranks runnable, unclaimed tasks by priority then age' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'low')
        described_class.create(root: root, workflow: 'feature', title: 'high', priority: 5)
        result = described_class.available(root: root)
        expect(result).to be_ok
        expect(result.value[:available].map { |c| c['task_id'] }).to eq(%w[TASK-0002 TASK-0001])
      end
    end

    it 'excludes claimed tasks' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'one')
        described_class.create(root: root, workflow: 'feature', title: 'two')
        described_class.claim(root: root, task_id: 'TASK-0001')
        result = described_class.available(root: root)
        expect(result.value[:available].map { |c| c['task_id'] }).to eq(['TASK-0002'])
      end
    end

    it 'excludes abandoned tasks and tasks without ready work' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'gone')
        described_class.abandon(root: root, task_id: 'TASK-0001')
        result = described_class.available(root: root)
        expect(result.value[:available]).to eq([])
      end
    end

    it 'stays dependency-blind by default: a dep-blocked task is still present' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'dep')
        described_class.create(root: root, workflow: 'feature', title: 'blocked')
        described_class.add_dependency(root: root, task_id: 'TASK-0002', depends_on: 'TASK-0001')
        result = described_class.available(root: root)
        expect(result.value[:available].map { |c| c['task_id'] }).to include('TASK-0002')
      end
    end

    it 'stays dependency-blind by default: an on_hold task is still present' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        described_class.create(root: root, workflow: 'feature', title: 'parked')
        described_class.set_status(root: root, task_id: 'TASK-0001', status: 'on_hold')
        result = described_class.available(root: root)
        expect(result.value[:available].map { |c| c['task_id'] }).to include('TASK-0001')
      end
    end

    context 'with dep_aware: true' do
      it 'excludes a dep-blocked task while its dependency is unfinished' do
        with_tmp_project do |root|
          init_project(root)
          seed_feature_workflow(root)
          described_class.create(root: root, workflow: 'feature', title: 'dep')
          described_class.create(root: root, workflow: 'feature', title: 'blocked')
          described_class.add_dependency(root: root, task_id: 'TASK-0002', depends_on: 'TASK-0001')
          ids = described_class.available(root: root, dep_aware: true).value[:available].map { |c| c['task_id'] }
          expect(ids).to include('TASK-0001')
          expect(ids).not_to include('TASK-0002')
        end
      end

      it 'excludes an on_hold task' do
        with_tmp_project do |root|
          init_project(root)
          seed_feature_workflow(root)
          described_class.create(root: root, workflow: 'feature', title: 'parked')
          described_class.create(root: root, workflow: 'feature', title: 'live')
          described_class.set_status(root: root, task_id: 'TASK-0001', status: 'on_hold')
          ids = described_class.available(root: root, dep_aware: true).value[:available].map { |c| c['task_id'] }
          expect(ids).not_to include('TASK-0001')
          expect(ids).to include('TASK-0002')
        end
      end

      it 'preserves the "has a ready step" filter and the candidate hash shape' do
        with_tmp_project do |root|
          init_project(root)
          seed_feature_workflow(root)
          described_class.create(root: root, workflow: 'feature', title: 'normal')
          candidate = described_class.available(root: root, dep_aware: true).value[:available].first
          expect(candidate['task_id']).to eq('TASK-0001')
          expect(candidate['ready_step_ids']).to eq(['noop'])
          expect(candidate['reason']).to be_a(String)
          # dep-aware shares the unified contract with plain available.
          expect(candidate.keys).to eq(
            %w[task_id title kind priority created_at status workflow ready_step_ids reason]
          )
          expect(candidate).not_to have_key('id')
        end
      end
    end
  end

  describe '.adopt' do
    it 'steals the claim and resets running steps to pending' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/.owl/workflows.yaml", <<~YAML)
          schema_version: 1
          workflows:
            feature:
              enabled: true
              source: "workflows/feature/workflow.yaml"
        YAML
        write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
          id: feature
          kind: feature
          steps:
            - id: a
            - id: b
              requires: ["a"]
          artifacts: []
        YAML
        described_class.create(root: root, workflow: 'feature', title: 't')
        Owl::Steps::Api.start(root: root, task_id: 'TASK-0001', step_id: 'a')

        result = described_class.adopt(root: root, task_id: 'TASK-0001')
        expect(result).to be_ok
        expect(result.value[:reopened]).to eq(['a'])
        expect(result.value[:token]).to be_a(String)

        step = YAML.safe_load(Pathname.new("#{root}/tasks/TASK-0001/task.yaml").read)['steps']
                   .find { |s| s['id'] == 'a' }
        expect(step['status']).to eq('pending')
        expect(Pathname.new("#{root}/.owl/local/claims/TASK-0001.yaml").exist?).to be(true)
      end
    end

    it 'propagates task_not_found for an unknown task' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.adopt(root: root, task_id: 'TASK-9999')
        expect(result).to be_err
        expect(result.code).to eq(:task_not_found)
      end
    end
  end

  describe 'internal helpers are private' do
    it 'does not expose with_backend or strip_local as public class methods' do
      expect(described_class).not_to respond_to(:with_backend)
      expect(described_class).not_to respond_to(:strip_local)
    end
  end
end
