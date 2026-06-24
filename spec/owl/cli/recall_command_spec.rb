# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/archive/api'
require 'owl/tasks/internal/atomic_yaml_writer'

RSpec.describe 'owl recall CLI' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def workflow_yaml
    <<~YAML
      id: feature
      kind: task
      artifacts:
        brief:
          type: brief
          storage:
            role: tasks
            path: "{{task.id}}/brief.md"
      steps:
        - id: brief
          creates: [brief]
        - id: verify
          requires: [brief]
        - id: publish
          requires: [verify]
    YAML
  end

  def setup_project(root, title:)
    run(['init', '--root', root.to_s], cwd: root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", workflow_yaml)

    _, stdout, = run(['task', 'create', '--workflow', 'feature', '--title', title,
                      '--root', root.to_s, '--json'], cwd: root)
    JSON.parse(stdout).dig('task', 'id')
  end

  def force_done(root, task_id)
    task_path = Pathname.new(root) + 'tasks' + task_id + 'task.yaml'
    payload = YAML.safe_load(task_path.read, aliases: false, permitted_classes: [Time])
    payload['steps'].each { |s| s['status'] = 'done' }
    Owl::Tasks::Internal::AtomicYamlWriter.write(path: task_path, payload: payload)
  end

  def archive(root, title:, brief:)
    task_id = setup_project(root, title: title)
    write("#{root}/tasks/#{task_id}/brief.md", brief)
    force_done(root, task_id)
    Owl::Archive::Api.archive_task(root: root, task_id: task_id, now: Time.utc(2026, 5, 17, 12, 0, 0))
    task_id
  end

  def active(root, title:, brief: nil)
    task_id = setup_project(root, title: title)
    write("#{root}/tasks/#{task_id}/brief.md", brief) if brief
    task_id
  end

  it 'emits {ok:true, matches:[{task_id,title,score,snippet}]} for a matching query' do
    with_tmp_project do |root|
      task_id = archive(root, title: 'Spec validation engine',
                              brief: "# Problem\nsemantic spec validation\n# Goal\nvalidate specs\n")

      exit_code, stdout, = run(['recall', 'spec', 'validation', '--root', root.to_s, '--json'], cwd: root)
      body = JSON.parse(stdout)

      expect(exit_code).to eq(0)
      expect(body['ok']).to be(true)
      first = body['matches'].first
      expect(first['task_id']).to eq(task_id)
      expect(first.keys).to contain_exactly('task_id', 'title', 'score', 'snippet', 'scope')
      expect(first['score']).to be > 0
      expect(first['scope']).to eq('archived')
    end
  end

  it 'honors --limit by truncating the match list' do
    with_tmp_project do |root|
      3.times { |i| archive(root, title: "spec task #{i}", brief: "# Problem\nspec validation\n") }

      _, stdout, = run(['recall', 'spec validation', '--limit', '2', '--root', root.to_s, '--json'], cwd: root)
      expect(JSON.parse(stdout)['matches'].length).to eq(2)
    end
  end

  it 'returns {ok:true, matches:[]} at exit 0 for an empty query (does not crash)' do
    with_tmp_project do |root|
      archive(root, title: 'Anything', brief: "# Problem\nx\n")

      exit_code, stdout, = run(['recall', '', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      expect(JSON.parse(stdout)).to eq('ok' => true, 'matches' => [])
    end
  end

  it 'returns {ok:true, matches:[]} at exit 0 when nothing matches' do
    with_tmp_project do |root|
      archive(root, title: 'Cartography', brief: "# Problem\nlunar maps\n")

      exit_code, stdout, = run(['recall', 'kubernetes ingress', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      expect(JSON.parse(stdout)['matches']).to eq([])
    end
  end

  it 'prints a plain-text list under --no-json' do
    with_tmp_project do |root|
      archive(root, title: 'Spec validation engine', brief: "# Problem\nspec validation\n")

      exit_code, stdout, = run(['recall', 'spec validation', '--no-json', '--root', root.to_s], cwd: root)
      expect(exit_code).to eq(0)
      expect(stdout).to include('Spec validation engine')
    end
  end

  it 'prints a friendly empty line under --no-json with no matches' do
    with_tmp_project do |root|
      setup_project(root, title: 'live only')
      exit_code, stdout, = run(['recall', 'whatever meaningful', '--no-json', '--root', root.to_s], cwd: root)
      expect(exit_code).to eq(0)
      expect(stdout).to include('No similar archived tasks found.')
    end
  end

  it 'reports invalid_arguments for a bad --limit value' do
    with_tmp_project do |root|
      setup_project(root, title: 't')
      exit_code, _, stderr = run(['recall', 'x', '--limit', 'NaN', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(1)
      expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
    end
  end

  it 'finds an active task by its brief under --scope active, tagged scope:active' do
    with_tmp_project do |root|
      task_id = active(root, title: 'Active recall feature',
                             brief: "# Problem\nactive tracker corpus token\n# Goal\nfind me\n")
      archive(root, title: 'Archived noise', brief: "# Problem\narchived widgets\n# Goal\nx\n")

      exit_code, stdout, = run(['recall', 'active tracker corpus token', '--scope', 'active',
                                '--root', root.to_s, '--json'], cwd: root)
      matches = JSON.parse(stdout)['matches']

      expect(exit_code).to eq(0)
      expect(matches.map { |m| m['task_id'] }).to include(task_id)
      expect(matches.map { |m| m['scope'] }.uniq).to eq(['active'])
    end
  end

  it 'searches both areas under --scope all with per-match scope labels' do
    with_tmp_project do |root|
      archive(root, title: 'Archived corpus item', brief: "# Problem\nscope all shared token\n# Goal\nx\n")
      active(root, title: 'Active corpus item', brief: "# Problem\nscope all shared token\n# Goal\nx\n")

      _, stdout, = run(['recall', 'scope all shared token', '--scope', 'all', '--root', root.to_s, '--json'], cwd: root)
      matches = JSON.parse(stdout)['matches']

      expect(matches.map { |m| m['scope'] }.sort).to eq(%w[active archived])
    end
  end

  it 'defaults to --scope archive (active tasks excluded)' do
    with_tmp_project do |root|
      archived_id = archive(root, title: 'Archived default item', brief: "# Problem\ndefault scope token\n# Goal\nx\n")
      active(root, title: 'Active default item', brief: "# Problem\ndefault scope token\n# Goal\nx\n")

      _, stdout, = run(['recall', 'default scope token', '--root', root.to_s, '--json'], cwd: root)
      matches = JSON.parse(stdout)['matches']

      expect(matches.map { |m| m['task_id'] }).to eq([archived_id])
      expect(matches.map { |m| m['scope'] }.uniq).to eq(['archived'])
    end
  end

  it 'reports invalid_scope (exit 1) for an unknown --scope' do
    with_tmp_project do |root|
      setup_project(root, title: 't')
      exit_code, _, stderr = run(['recall', 'x', '--scope', 'bogus', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(1)
      expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_scope')
    end
  end
end
