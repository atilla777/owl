# frozen_string_literal: true

require 'pathname'
require 'yaml'

require 'owl/tasks/api'
require 'owl/tasks/backends/filesystem'
require 'owl/tasks/internal/atomic_yaml_writer'
require 'owl/cli/internal/commands/init'

RSpec.describe Owl::Tasks::Backends::Filesystem do
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
      steps:
        - id: noop
          kind: noop
      artifacts: []
    YAML
  end

  it 'includes the Owl::Tasks::Backend contract' do
    expect(described_class.included_modules).to include(Owl::Tasks::Backend)
  end

  describe 'instance contract' do
    it 'responds to every method declared by Owl::Tasks::Backend' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)
        Owl::Tasks::Backend.instance_methods(false).each do |method_name|
          expect(backend).to respond_to(method_name), "missing backend method: #{method_name}"
        end
      end
    end
  end

  describe 'happy-path delegation' do
    it 'create + list + inspect_task return the same results as the legacy api' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        backend = described_class.new(root: root)

        create_result = backend.create(workflow: 'feature', title: 'first')
        expect(create_result).to be_ok
        expect(create_result.value[:task_id]).to eq('TASK-0001')

        list_result = backend.list
        expect(list_result).to be_ok
        # list projects to the unified output contract: identity under `task_id`,
        # never the storage key `id`.
        expect(list_result.value[:tasks].map { |t| t['task_id'] }).to eq(['TASK-0001'])
        expect(list_result.value[:tasks].first).not_to have_key('id')

        # The on-disk index keeps its storage `id` key (output-only rename).
        on_disk = YAML.safe_load(Pathname.new("#{root}/tasks/index.yaml").read)
        expect(on_disk['tasks'].map { |t| t['id'] }).to eq(['TASK-0001'])

        inspect_result = backend.inspect_task(task_id: 'TASK-0001')
        expect(inspect_result).to be_ok
        expect(inspect_result.value[:payload]['title']).to eq('first')
      end
    end

    it 'use + current round-trip' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        backend = described_class.new(root: root)
        backend.create(workflow: 'feature', title: 'first')

        backend.use(task_id: 'TASK-0001')
        current_result = backend.current
        expect(current_result).to be_ok
        expect(current_result.value[:task_id]).to eq('TASK-0001')
      end
    end
  end

  describe '#archive_task' do
    it 'archives a task whose workflow is completed' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        backend = described_class.new(root: root)

        create_result = backend.create(workflow: 'feature', title: 'archived one')
        task_id = create_result.value[:task_id]

        task_path = Pathname.new("#{root}/tasks/#{task_id}/task.yaml")
        payload = YAML.safe_load(task_path.read, aliases: false, permitted_classes: [Time])
        payload['steps'].each { |step| step['status'] = 'done' }
        Owl::Tasks::Internal::AtomicYamlWriter.write(path: task_path, payload: payload)

        result = backend.archive_task(task_id: task_id, now: Time.utc(2026, 5, 18, 12, 0, 0))

        aggregate_failures do
          expect(result).to be_ok
          expect(result.value[:task_id]).to eq(task_id)
          expect(result.value[:archived_at]).to eq('2026-05-18T12:00:00Z')
          expect(result.value[:from]).to include("tasks/#{task_id}")
          expect(Pathname.new(result.value[:to]).exist?).to be(true)
          expect(result.value[:current_reset]).to be(false)
        end
      end
    end
  end

  describe '#create after every task is archived' do
    it 'does not reuse archived ids nor overwrite archived task.yaml' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        backend = described_class.new(root: root)

        first = backend.create(workflow: 'feature', title: 'archived one')
        first_id = first.value[:task_id]

        task_path = Pathname.new("#{root}/tasks/#{first_id}/task.yaml")
        payload = YAML.safe_load(task_path.read, aliases: false, permitted_classes: [Time])
        payload['steps'].each { |step| step['status'] = 'done' }
        Owl::Tasks::Internal::AtomicYamlWriter.write(path: task_path, payload: payload)
        archived = backend.archive_task(task_id: first_id, now: Time.utc(2026, 5, 18, 12, 0, 0))
        archived_yaml = Pathname.new(archived.value[:to]).join('task.yaml')

        # The live work zone is now empty; a naive allocator would reset to TASK-0001
        # and TaskWriter would resolve it onto the archived directory, overwriting it.
        second = backend.create(workflow: 'feature', title: 'second')

        aggregate_failures do
          expect(second).to be_ok
          expect(second.value[:task_id]).not_to eq(first_id)
          expect(second.value[:task_path]).to include("tasks/#{second.value[:task_id]}/")
          archived_payload = YAML.safe_load(archived_yaml.read, aliases: false, permitted_classes: [Time])
          expect(archived_payload['id']).to eq(first_id)
          expect(archived_payload['title']).to eq('archived one')
        end
      end
    end
  end
end
