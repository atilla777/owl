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

  # Create a live (non-terminal) task, optionally writing its brief.
  def active_task(root, title:, brief: nil)
    task_id = setup_project(root, title: title)
    write("#{root}/tasks/#{task_id}/brief.md", brief) if brief
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
        expect(match.keys).to contain_exactly(:task_id, :title, :score, :snippet, :scope)
        expect(match[:score]).to be > 0
        expect(match[:snippet]).to be_a(String)
        expect(match[:scope]).to eq('archived')
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

  describe '.recall scope' do
    it 'defaults to archive, excluding active tasks' do
      with_tmp_project do |root|
        archived_id = archive_task(root, title: 'Archived recall corpus item',
                                         brief: "# Problem\nshared distinctive corpus token\n# Goal\nx\n")
        active_task(root, title: 'Active other item',
                          brief: "# Problem\nshared distinctive corpus token\n# Goal\nx\n")

        matches = described_class.recall(root: root, query: 'shared distinctive corpus token')

        expect(matches.map { |m| m[:task_id] }).to eq([archived_id])
        expect(matches.map { |m| m[:scope] }.uniq).to eq(['archived'])
      end
    end

    it 'finds an active task by its brief text under scope active' do
      with_tmp_project do |root|
        active_id = active_task(root, title: 'Active feature',
                                      brief: "# Problem\nactive tracker recall corpus\n# Goal\nfind me\n")
        archive_task(root, title: 'Archived feature',
                           brief: "# Problem\narchived widgets gears\n# Goal\nx\n")

        matches = described_class.recall(root: root, query: 'active tracker recall corpus', scope: 'active')

        expect(matches.map { |m| m[:task_id] }).to include(active_id)
        expect(matches.map { |m| m[:scope] }.uniq).to eq(['active'])
      end
    end

    it 'falls back to the title for an active task without a brief' do
      with_tmp_project do |root|
        active_id = active_task(root, title: 'Nobrief distinctive heading')

        matches = described_class.recall(root: root, query: 'nobrief distinctive heading', scope: 'active')

        expect(matches.map { |m| m[:task_id] }).to include(active_id)
      end
    end

    it 'searches both areas under scope all and labels each match' do
      with_tmp_project do |root|
        archive_task(root, title: 'Archived corpus item',
                           brief: "# Problem\nrecall scope token alpha\n# Goal\nx\n")
        active_task(root, title: 'Active corpus item',
                          brief: "# Problem\nrecall scope token alpha\n# Goal\nx\n")

        matches = described_class.recall(root: root, query: 'recall scope token alpha', scope: 'all')

        expect(matches.map { |m| m[:scope] }.sort).to eq(%w[active archived])
      end
    end

    it 'returns [] under scope active when there are no active tasks' do
      with_tmp_project do |root|
        archive_task(root, title: 'Archived only', brief: "# Problem\narchived token\n")

        expect(described_class.recall(root: root, query: 'archived token', scope: 'active')).to eq([])
      end
    end

    it 'returns an invalid_scope error for an unknown scope' do
      with_tmp_project do |root|
        result = described_class.recall(root: root, query: 'anything', scope: 'bogus')

        expect(result).to be_a(Owl::Result::Err)
        expect(result.code).to eq(:invalid_scope)
        expect(result.details[:allowed]).to eq(%w[active archive all])
      end
    end
  end
end
