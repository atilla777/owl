# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/recall/api'
require 'owl/cli/api'
require 'owl/tasks/internal/atomic_yaml_writer'

RSpec.describe Owl::Recall::Api do
  def run_cli(argv, cwd:)
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
    run_cli(['init', '--root', root.to_s], cwd: root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", workflow_yaml)

    _, stdout, = run_cli(['task', 'create', '--workflow', 'feature', '--title', title,
                          '--root', root.to_s, '--json'], cwd: root)
    JSON.parse(stdout).dig('task', 'id')
  end

  def force_step_status(root, task_id, step_id, status)
    task_path = Pathname.new(root) + 'tasks' + task_id + 'task.yaml'
    payload = YAML.safe_load(task_path.read, aliases: false, permitted_classes: [Time])
    payload['steps'].find { |s| s['id'] == step_id }['status'] = status
    Owl::Tasks::Internal::AtomicYamlWriter.write(path: task_path, payload: payload)
  end

  def archive_task(root, title:, brief: nil)
    task_id = setup_project(root, title: title)
    write("#{root}/tasks/#{task_id}/brief.md", brief) if brief
    %w[brief verify publish].each { |s| force_step_status(root, task_id, s, 'done') }
    Owl::Archive::Api.archive_task(root: root, task_id: task_id, now: Time.utc(2026, 5, 17, 12, 0, 0))
    task_id
  end

  describe '.recall' do
    it 'returns ranked {task_id,title,score,snippet} hashes sorted by score desc' do
      with_tmp_project do |root|
        archive_task(root, title: 'Archive read command',
                           brief: "# Problem\nRead archived tasks and their artifacts.\n# Goal\nExpose archive read.\n")
        archive_task(root, title: 'Unrelated plumbing',
                           brief: "# Problem\nWidgets and gears.\n# Goal\nMore gears.\n")

        matches = described_class.recall(root: root, query: 'read archived tasks artifacts')

        expect(matches).not_to be_empty
        expect(matches.first[:title]).to eq('Archive read command')
        match = matches.first
        expect(match.keys).to contain_exactly(:task_id, :title, :score, :snippet)
        expect(match[:score]).to be > 0
        expect(match[:snippet]).to be_a(String)
        scores = matches.map { |m| m[:score] }
        expect(scores).to eq(scores.sort.reverse)
      end
    end

    it 'truncates the result set to the requested limit' do
      with_tmp_project do |root|
        3.times { |i| archive_task(root, title: "Spec validation task #{i}", brief: "# Problem\nspec validation\n") }

        matches = described_class.recall(root: root, query: 'spec validation', limit: 2)
        expect(matches.length).to eq(2)
      end
    end

    it 'clamps a negative limit to 0 instead of raising' do
      with_tmp_project do |root|
        archive_task(root, title: 'Spec validation task', brief: "# Problem\nspec validation\n")

        expect { described_class.recall(root: root, query: 'spec validation', limit: -1) }.not_to raise_error
        expect(described_class.recall(root: root, query: 'spec validation', limit: -1)).to eq([])
      end
    end

    it 'returns [] for an empty query without touching the corpus' do
      with_tmp_project do |root|
        archive_task(root, title: 'Anything', brief: "# Problem\nx\n")
        expect(described_class.recall(root: root, query: '')).to eq([])
      end
    end

    it 'returns [] for a stopword-only query' do
      with_tmp_project do |root|
        archive_task(root, title: 'Anything', brief: "# Problem\nx\n")
        expect(described_class.recall(root: root, query: 'the and of to')).to eq([])
      end
    end

    it 'returns [] when the archive is empty' do
      with_tmp_project do |root|
        setup_project(root, title: 'live only')
        expect(described_class.recall(root: root, query: 'anything meaningful')).to eq([])
      end
    end

    it 'returns [] when no archived task shares significant tokens' do
      with_tmp_project do |root|
        archive_task(root, title: 'Cartography of moons',
                           brief: "# Problem\nlunar mapping\n# Goal\nmaps\n")
        expect(described_class.recall(root: root, query: 'kubernetes networking ingress')).to eq([])
      end
    end

    it 'uses the default limit constant' do
      expect(described_class::DEFAULT_LIMIT).to eq(10)
    end
  end
end
