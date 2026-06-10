# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/publish/backend'
require 'owl/publish/backends/filesystem'
require 'owl/tasks/internal/atomic_yaml_writer'

RSpec.describe Owl::Publish::Backends::Filesystem do
  def run_cli(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def setup_project(root, workflow_yaml: nil)
    run_cli(['init', '--root', root.to_s], cwd: root)

    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML

    body = workflow_yaml || default_feature_workflow
    write("#{root}/.owl/workflows/feature/workflow.yaml", body)

    _, stdout, = run_cli(['task', 'create', '--workflow', 'feature', '--title', 't',
                          '--root', root.to_s, '--json'], cwd: root)
    JSON.parse(stdout).dig('task', 'id')
  end

  def default_feature_workflow
    <<~YAML
      id: feature
      kind: task
      artifacts:
        spec:
          type: spec
          storage:
            role: tasks
            path: "{{task.id}}/spec.md"
      publishes:
        - from: "{{task.id}}/spec.md"
          to: "{{task.id}}/spec.md"
      steps:
        - id: specify
          creates: [spec]
        - id: verify
          requires: [specify]
        - id: publish
          requires: [verify]
    YAML
  end

  def force_step_status(root, task_id, step_id, status)
    task_path = Pathname.new(root) + 'tasks' + task_id + 'task.yaml'
    payload = YAML.safe_load(task_path.read, aliases: false, permitted_classes: [Time])
    step = payload['steps'].find { |s| s['id'] == step_id }
    step['status'] = status
    Owl::Tasks::Internal::AtomicYamlWriter.write(path: task_path, payload: payload)
  end

  def mark_ready_chain(root, task_id)
    force_step_status(root, task_id, 'specify', 'done')
    force_step_status(root, task_id, 'verify', 'done')
  end

  it 'includes the Owl::Publish::Backend contract' do
    expect(described_class.included_modules).to include(Owl::Publish::Backend)
  end

  describe 'instance contract' do
    it 'responds to every method declared by Owl::Publish::Backend' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)
        Owl::Publish::Backend.instance_methods(false).each do |method_name|
          expect(backend).to respond_to(method_name), "missing backend method: #{method_name}"
        end
      end
    end
  end

  describe '#run' do
    it 'creates the target file when it does not exist (action=created)' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        write("#{root}/tasks/#{task_id}/spec.md", "# spec body\n")
        mark_ready_chain(root, task_id)

        result = described_class.new(root: root).run(task_id: task_id, dry_run: false)
        expect(result).to be_ok
        expect(result.value[:dry_run]).to be(false)
        expect(result.value[:step_status]).to eq('ready')

        rules = result.value[:results]
        expect(rules.length).to eq(1)
        expect(rules.first['action']).to eq('created')
        expect(rules.first['backup_path']).to be_nil

        target = Pathname.new("#{root}/docs/#{task_id}/spec.md")
        expect(target.read).to eq("# spec body\n")
      end
    end

    it 'creates a backup before replacing an existing target (action=replaced)' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        write("#{root}/tasks/#{task_id}/spec.md", "# new body\n")
        write("#{root}/docs/#{task_id}/spec.md", "# old body\n")
        mark_ready_chain(root, task_id)

        result = described_class.new(root: root).run(
          task_id: task_id, dry_run: false, now: Time.utc(2026, 5, 20, 12, 34, 56)
        )
        expect(result).to be_ok
        rule = result.value[:results].first
        expect(rule['action']).to eq('replaced')
        expect(rule['backup_path']).to end_with('spec.md.bak.20260520T123456Z')

        backup = Pathname.new(rule['backup_path'])
        expect(backup.read).to eq("# old body\n")
        expect(Pathname.new("#{root}/docs/#{task_id}/spec.md").read).to eq("# new body\n")
      end
    end

    it 'does not touch the filesystem in dry-run mode' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        write("#{root}/tasks/#{task_id}/spec.md", "# spec\n")
        mark_ready_chain(root, task_id)

        result = described_class.new(root: root).run(task_id: task_id, dry_run: true)
        expect(result).to be_ok
        rule = result.value[:results].first
        expect(rule['action']).to eq('created')
        expect(rule['dry_run']).to be(true)
        expect(rule['backup_path']).to be_nil

        expect(Pathname.new("#{root}/docs/#{task_id}/spec.md").exist?).to be(false)
      end
    end

    it 'returns source_missing when the source artifact does not exist' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        mark_ready_chain(root, task_id)
        result = described_class.new(root: root).run(task_id: task_id)
        expect(result).to be_err
        expect(result.code).to eq(:source_missing)
      end
    end

    it 'returns write_failed when the target write raises and there is no prior target' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        write("#{root}/tasks/#{task_id}/spec.md", "# spec\n")
        mark_ready_chain(root, task_id)

        allow(Owl::Storage::Internal::FilesystemBackend).to receive(:write).and_raise(Errno::EACCES, 'denied')

        result = described_class.new(root: root).run(task_id: task_id, dry_run: false)
        expect(result).to be_err
        expect(result.code).to eq(:write_failed)
      end
    end

    it 'returns task_workflow_missing when task.yaml has no workflow key' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        task_path = Pathname.new(root) + 'tasks' + task_id + 'task.yaml'
        payload = YAML.safe_load(task_path.read, aliases: false, permitted_classes: [Time])
        payload.delete('workflow')
        Owl::Tasks::Internal::AtomicYamlWriter.write(path: task_path, payload: payload)

        result = described_class.new(root: root).run(task_id: task_id)
        expect(result).to be_err
        expect(result.code).to eq(:task_workflow_missing)
      end
    end

    it 'returns workflow_source_missing when the workflow source file is gone' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        Pathname.new("#{root}/.owl/workflows/feature/workflow.yaml").delete

        result = described_class.new(root: root).run(task_id: task_id)
        expect(result).to be_err
        expect(result.code).to eq(:workflow_source_missing)
      end
    end

    it 'returns publish_step_not_ready when prerequisites are not yet done' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        write("#{root}/tasks/#{task_id}/spec.md", "# spec\n")
        result = described_class.new(root: root).run(task_id: task_id)
        expect(result).to be_err
        expect(result.code).to eq(:publish_step_not_ready)
      end
    end

    it 'returns no_publishable_step when the workflow has publish step but no rules' do
      with_tmp_project do |root|
        workflow_yaml = <<~YAML
          id: feature
          kind: task
          artifacts:
            spec:
              type: spec
              storage:
                role: tasks
                path: "{{task.id}}/spec.md"
          steps:
            - id: specify
              creates: [spec]
            - id: verify
              requires: [specify]
            - id: publish
              requires: [verify]
        YAML
        task_id = setup_project(root, workflow_yaml: workflow_yaml)
        mark_ready_chain(root, task_id)
        result = described_class.new(root: root).run(task_id: task_id)
        expect(result).to be_err
        expect(result.code).to eq(:no_publishable_step)
      end
    end

    it 'resolves the publishing step by the `publishes: true` marker (not named publish)' do
      with_tmp_project do |root|
        workflow_yaml = <<~YAML
          id: feature
          kind: task
          artifacts:
            spec:
              type: spec
              storage:
                role: tasks
                path: "{{task.id}}/spec.md"
          publishes:
            - from: "{{task.id}}/spec.md"
              to: "{{task.id}}/spec.md"
          steps:
            - id: specify
              creates: [spec]
            - id: verify
              requires: [specify]
            - id: merge_docs
              publishes: true
              requires: [verify]
        YAML
        task_id = setup_project(root, workflow_yaml: workflow_yaml)
        write("#{root}/tasks/#{task_id}/spec.md", "# spec\n")
        mark_ready_chain(root, task_id)

        result = described_class.new(root: root).run(task_id: task_id, dry_run: false)
        expect(result).to be_ok
        expect(result.value[:results].first['action']).to eq('created')
        expect(Pathname.new("#{root}/docs/#{task_id}/spec.md").read).to eq("# spec\n")
      end
    end

    it 'treats a missing source for an optional rule as a no-op (skipped_missing_source)' do
      with_tmp_project do |root|
        workflow_yaml = <<~YAML
          id: feature
          kind: task
          artifacts:
            spec:
              type: spec
              storage:
                role: tasks
                path: "{{task.id}}/spec.md"
          publishes:
            - from: "{{task.id}}/spec.md"
              to: "{{task.id}}/spec.md"
              optional: true
          steps:
            - id: specify
              creates: [spec]
            - id: verify
              requires: [specify]
            - id: publish
              requires: [verify]
        YAML
        task_id = setup_project(root, workflow_yaml: workflow_yaml)
        mark_ready_chain(root, task_id) # source spec.md deliberately absent

        result = described_class.new(root: root).run(task_id: task_id, dry_run: false)
        expect(result).to be_ok
        expect(result.value[:results].first['action']).to eq('skipped_missing_source')
        expect(Pathname.new("#{root}/docs/#{task_id}/spec.md").exist?).to be(false)
      end
    end
  end
end
