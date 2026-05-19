# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/archive/api'
require 'owl/cli/api'
require 'owl/tasks/internal/atomic_yaml_writer'

RSpec.describe 'composite archive (independent of children)' do
  def run_cli(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def default_workflow_yaml
    <<~YAML
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
  end

  def setup_project(root)
    run_cli(['init', '--root', root.to_s], cwd: root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", default_workflow_yaml)
  end

  def create_task(root:, title:, parent: nil)
    argv = ['task', 'create', '--workflow', 'feature', '--title', title,
            '--root', root.to_s, '--json']
    argv += ['--parent', parent] if parent
    _, stdout, = run_cli(argv, cwd: root)
    JSON.parse(stdout).dig('task', 'id')
  end

  def mark_composite(root, task_id)
    path = Pathname.new("#{root}/tasks/#{task_id}/task.yaml")
    payload = YAML.safe_load(path.read, aliases: false, permitted_classes: [Time])
    payload['kind'] = 'composite_task'
    Owl::Tasks::Internal::AtomicYamlWriter.write(path: path, payload: payload)
  end

  def force_step_status(root, task_id, step_id, status)
    path = Pathname.new("#{root}/tasks/#{task_id}/task.yaml")
    payload = YAML.safe_load(path.read, aliases: false, permitted_classes: [Time])
    payload['steps'].find { |s| s['id'] == step_id }['status'] = status
    Owl::Tasks::Internal::AtomicYamlWriter.write(path: path, payload: payload)
  end

  def mark_all_done(root, task_id, step_ids)
    step_ids.each { |id| force_step_status(root, task_id, id, 'done') }
  end

  let(:now) { Time.utc(2026, 5, 18, 12, 0, 0) }

  it 'archives a composite parent and leaves children active even when children are unfinished' do
    with_tmp_project do |root|
      setup_project(root)
      parent_id = create_task(root: root, title: 'parent')
      mark_composite(root, parent_id)
      child_a = create_task(root: root, title: 'child a', parent: parent_id)
      child_b = create_task(root: root, title: 'child b', parent: parent_id)
      run_cli(['task', 'index', 'rebuild', '--root', root.to_s, '--json'], cwd: root)

      mark_all_done(root, parent_id, %w[specify verify publish])
      mark_all_done(root, child_a, %w[specify]) # child_a partially done
      # child_b stays entirely pending

      result = Owl::Archive::Api.archive_task(root: root, task_id: parent_id, now: now)
      expect(result).to be_ok

      expect((Pathname.new(root) + 'tasks' + parent_id).exist?).to be(false)
      expect((Pathname.new(root) + 'tasks' + child_a).directory?).to be(true)
      expect((Pathname.new(root) + 'tasks' + child_b).directory?).to be(true)

      archive_root = Pathname.new("#{root}/tasks/archive")
      archived_dirs = archive_root.children.select(&:directory?).map { |c| c.basename.to_s }
      expect(archived_dirs.size).to eq(1)
      expect(archived_dirs.first).to include(parent_id)
    end
  end

  it 'allows children to archive themselves later (independently of parent)' do
    with_tmp_project do |root|
      setup_project(root)
      parent_id = create_task(root: root, title: 'parent')
      mark_composite(root, parent_id)
      child = create_task(root: root, title: 'child', parent: parent_id)
      run_cli(['task', 'index', 'rebuild', '--root', root.to_s, '--json'], cwd: root)

      mark_all_done(root, parent_id, %w[specify verify publish])
      Owl::Archive::Api.archive_task(root: root, task_id: parent_id, now: now)

      mark_all_done(root, child, %w[specify verify publish])
      result = Owl::Archive::Api.archive_task(root: root, task_id: child,
                                              now: Time.utc(2026, 5, 19, 12, 0, 0))
      expect(result).to be_ok
      expect((Pathname.new(root) + 'tasks' + child).exist?).to be(false)
    end
  end
end
