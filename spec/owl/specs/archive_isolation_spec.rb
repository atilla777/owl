# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/tasks/internal/atomic_yaml_writer'

# `owl archive` only moves `tasks/<ID>/`. A spec under `specs/<domain>/spec.md`
# is project-level and must survive task archival untouched.
RSpec.describe 'specs survive task archival' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def setup_project(root)
    run(['init', '--root', root.to_s], cwd: root)
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
      steps:
        - id: specify
        - id: verify
          requires: [specify]
    YAML

    _, stdout, = run(['task', 'create', '--workflow', 'feature', '--title', 't',
                      '--root', root.to_s, '--json'], cwd: root)
    JSON.parse(stdout).dig('task', 'id')
  end

  def force_step_done(root, task_id, step_id)
    task_path = Pathname.new(root) + 'tasks' + task_id + 'task.yaml'
    payload = YAML.safe_load(task_path.read, aliases: false, permitted_classes: [Time])
    payload['steps'].find { |s| s['id'] == step_id }['status'] = 'done'
    Owl::Tasks::Internal::AtomicYamlWriter.write(path: task_path, payload: payload)
  end

  it 'leaves specs/<domain>/spec.md in place after archiving a task' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      spec_body = Pathname.new("#{root}/.owl/artifacts/spec/templates/default.md").read
      write("#{root}/specs/ui/spec.md", spec_body)

      %w[specify verify].each { |s| force_step_done(root, task_id, s) }
      exit_code, = run(['archive', task_id, '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)

      # Task is gone from the work zone, but the spec is untouched.
      expect(Pathname.new("#{root}/tasks/#{task_id}").exist?).to be(false)
      spec_path = Pathname.new("#{root}/specs/ui/spec.md")
      expect(spec_path.exist?).to be(true)
      expect(spec_path.read).to eq(spec_body)

      # And the spec is not swept into the archive tree.
      archived = Pathname.new("#{root}/tasks/archive")
      expect(Dir.glob("#{archived}/**/specs")).to be_empty

      _, stdout, = run(['spec', 'show', 'ui', '--root', root.to_s, '--json'], cwd: root)
      expect(JSON.parse(stdout)['body']).to eq(spec_body)
    end
  end
end
