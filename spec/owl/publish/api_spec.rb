# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/publish/api'
require 'owl/tasks/internal/task_reader'
require 'owl/tasks/internal/atomic_yaml_writer'

RSpec.describe Owl::Publish::Api do
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

  def design_feature_workflow
    <<~YAML
      id: feature
      kind: task
      artifacts:
        design:
          type: design
          optional: true
          storage:
            role: tasks
            path: "{{task.id}}/design.md"
      publishes:
        - from: "{{task.id}}/design.md"
          to: "{{task.id}}/design.md"
          optional: true
      steps:
        - id: specify
          creates: [design]
        - id: verify
          requires: [specify]
        - id: publish
          requires: [verify]
    YAML
  end

  def design_doc(status)
    <<~MD
      ---
      status: #{status}
      summary: "Design summary for the index"
      ---
      # Design

      Body.
    MD
  end

  def force_step_status(root, task_id, step_id, status)
    task_path = Pathname.new(root) + 'tasks' + task_id + 'task.yaml'
    payload = YAML.safe_load(task_path.read, aliases: false, permitted_classes: [Time])
    step = payload['steps'].find { |s| s['id'] == step_id }
    step['status'] = status
    Owl::Tasks::Internal::AtomicYamlWriter.write(path: task_path, payload: payload)
  end

  def mark_ready_chain(root, task_id)
    # specify done, verify done → publish becomes ready.
    force_step_status(root, task_id, 'specify', 'done')
    force_step_status(root, task_id, 'verify', 'done')
  end

  describe '#run' do
    it 'creates the target file when it does not exist (action=created)' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        write("#{root}/tasks/#{task_id}/spec.md", "# spec body\n")
        mark_ready_chain(root, task_id)

        result = described_class.run(root: root, task_id: task_id, dry_run: false)
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

        result = described_class.run(root: root, task_id: task_id, dry_run: false,
                                     now: Time.utc(2026, 5, 17, 12, 34, 56))
        expect(result).to be_ok
        rule = result.value[:results].first
        expect(rule['action']).to eq('replaced')
        expect(rule['backup_path']).to end_with('spec.md.bak.20260517T123456Z')

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

        result = described_class.run(root: root, task_id: task_id, dry_run: true)
        expect(result).to be_ok
        rule = result.value[:results].first
        expect(rule['action']).to eq('created')
        expect(rule['dry_run']).to be(true)
        expect(rule['backup_path']).to be_nil

        expect(Pathname.new("#{root}/docs/#{task_id}/spec.md").exist?).to be(false)
      end
    end

    it 'returns no_publishable_step when the workflow has no publish step' do
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
        YAML
        task_id = setup_project(root, workflow_yaml: workflow_yaml)
        result = described_class.run(root: root, task_id: task_id)
        expect(result).to be_err
        expect(result.code).to eq(:no_publishable_step)
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
        result = described_class.run(root: root, task_id: task_id)
        expect(result).to be_err
        expect(result.code).to eq(:no_publishable_step)
      end
    end

    it 'returns publish_step_not_ready when prerequisites are not yet done' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        write("#{root}/tasks/#{task_id}/spec.md", "# spec\n")
        # do not mark verify as done

        result = described_class.run(root: root, task_id: task_id)
        expect(result).to be_err
        expect(result.code).to eq(:publish_step_not_ready)
      end
    end

    it 'accepts publish step when its stored status is done' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        write("#{root}/tasks/#{task_id}/spec.md", "# spec\n")
        mark_ready_chain(root, task_id)
        force_step_status(root, task_id, 'publish', 'done')

        result = described_class.run(root: root, task_id: task_id)
        expect(result).to be_ok
        expect(result.value[:step_status]).to eq('done')
      end
    end

    it 'accepts publish step when the harness has pre-started it (status running)' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        write("#{root}/tasks/#{task_id}/spec.md", "# spec\n")
        mark_ready_chain(root, task_id)
        force_step_status(root, task_id, 'publish', 'running')

        result = described_class.run(root: root, task_id: task_id, dry_run: false)
        expect(result).to be_ok
        expect(result.value[:step_status]).to eq('running')
        expect(result.value[:results].first['action']).to eq('created')
      end
    end

    it 'returns publish_step_not_ready when the step is pending and not in the ready set' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        write("#{root}/tasks/#{task_id}/spec.md", "# spec\n")
        # prerequisites are unmet, so publish is pending and not ready

        result = described_class.run(root: root, task_id: task_id)
        expect(result).to be_err
        expect(result.code).to eq(:publish_step_not_ready)
        expect(result.details[:current_status]).to eq('pending')
        expect(result.details[:acceptable_statuses]).to eq(%w[ready running done])
      end
    end

    it 'returns source_missing when the source artifact does not exist' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        mark_ready_chain(root, task_id)
        result = described_class.run(root: root, task_id: task_id)
        expect(result).to be_err
        expect(result.code).to eq(:source_missing)
      end
    end

    it 'returns backup_failed when the target file cannot be backed up' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        write("#{root}/tasks/#{task_id}/spec.md", "# new\n")
        target = Pathname.new("#{root}/docs/#{task_id}/spec.md")
        write(target, "# old\n")
        mark_ready_chain(root, task_id)

        allow(Owl::Storage::Internal::FilesystemBackend).to receive(:write).and_raise(Errno::EACCES, 'denied')

        result = described_class.run(root: root, task_id: task_id, dry_run: false)
        expect(result).to be_err
        expect(result.code).to eq(:backup_failed)
        expect(target.read).to eq("# old\n")
      end
    end

    it 'returns task_workflow_missing when task.yaml has no workflow key' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        task_path = Pathname.new(root) + 'tasks' + task_id + 'task.yaml'
        payload = YAML.safe_load(task_path.read, aliases: false, permitted_classes: [Time])
        payload.delete('workflow')
        Owl::Tasks::Internal::AtomicYamlWriter.write(path: task_path, payload: payload)

        result = described_class.run(root: root, task_id: task_id)
        expect(result).to be_err
        expect(result.code).to eq(:task_workflow_missing)
      end
    end

    it 'returns workflow_source_missing when the workflow source file is gone' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        Pathname.new("#{root}/.owl/workflows/feature/workflow.yaml").delete

        result = described_class.run(root: root, task_id: task_id)
        expect(result).to be_err
        expect(result.code).to eq(:workflow_source_missing)
      end
    end

    it 'rejects publishes rules with extra keys' do
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
              extra: oops
          steps:
            - id: specify
              creates: [spec]
            - id: publish
              requires: [specify]
        YAML
        task_id = setup_project(root, workflow_yaml: workflow_yaml)
        force_step_status(root, task_id, 'specify', 'done')

        result = described_class.run(root: root, task_id: task_id)
        expect(result).to be_err
        expect(result.code).to eq(:publishes_invalid)
      end
    end

    it 'exposes design_status and index keys (not_applicable for non-design rules)' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        write("#{root}/tasks/#{task_id}/spec.md", "# spec body\n")
        mark_ready_chain(root, task_id)

        result = described_class.run(root: root, task_id: task_id, dry_run: false)
        expect(result).to be_ok
        expect(result.value[:design_status]).to eq('not_applicable')
        expect(result.value[:index]).to eq(updated: true, path: 'docs/README.md')
        expect(Pathname.new("#{root}/docs/README.md").exist?).to be(true)
      end
    end
  end

  describe '#run design shipped-flip' do
    it 'flips approved design to shipped in both source and published copy' do
      with_tmp_project do |root|
        task_id = setup_project(root, workflow_yaml: design_feature_workflow)
        write("#{root}/tasks/#{task_id}/design.md", design_doc('approved'))
        mark_ready_chain(root, task_id)

        result = described_class.run(root: root, task_id: task_id, dry_run: false)
        expect(result).to be_ok
        expect(result.value[:design_status]).to eq('flipped_to_shipped')

        source = Pathname.new("#{root}/tasks/#{task_id}/design.md").read
        published = Pathname.new("#{root}/docs/#{task_id}/design.md").read
        expect(source).to include('status: shipped')
        expect(published).to include('status: shipped')
        expect(source).to eq(published)
      end
    end

    it 'does not flip on dry-run' do
      with_tmp_project do |root|
        task_id = setup_project(root, workflow_yaml: design_feature_workflow)
        write("#{root}/tasks/#{task_id}/design.md", design_doc('approved'))
        mark_ready_chain(root, task_id)

        result = described_class.run(root: root, task_id: task_id, dry_run: true)
        expect(result).to be_ok
        expect(result.value[:design_status]).to eq('not_applicable')
        expect(result.value[:index]).to eq(updated: false, path: 'docs/README.md')

        expect(Pathname.new("#{root}/tasks/#{task_id}/design.md").read).to include('status: approved')
        expect(Pathname.new("#{root}/docs/README.md").exist?).to be(false)
      end
    end

    it 'is idempotent: already shipped design reports already_shipped' do
      with_tmp_project do |root|
        task_id = setup_project(root, workflow_yaml: design_feature_workflow)
        write("#{root}/tasks/#{task_id}/design.md", design_doc('shipped'))
        mark_ready_chain(root, task_id)

        result = described_class.run(root: root, task_id: task_id, dry_run: false)
        expect(result).to be_ok
        expect(result.value[:design_status]).to eq('already_shipped')
        expect(Pathname.new("#{root}/tasks/#{task_id}/design.md").read).to include('status: shipped')
      end
    end

    it 'is not_applicable when the optional design source is missing' do
      with_tmp_project do |root|
        task_id = setup_project(root, workflow_yaml: design_feature_workflow)
        mark_ready_chain(root, task_id) # design.md deliberately absent

        result = described_class.run(root: root, task_id: task_id, dry_run: false)
        expect(result).to be_ok
        expect(result.value[:design_status]).to eq('not_applicable')
        expect(result.value[:results].first['action']).to eq('skipped_missing_source')
      end
    end
  end
end
