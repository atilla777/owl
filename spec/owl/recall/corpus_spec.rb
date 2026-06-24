# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/recall/internal/corpus_builder'
require 'owl/archive/api'
require 'owl/cli/api'
require 'owl/tasks/internal/atomic_yaml_writer'

RSpec.describe Owl::Recall::Internal::CorpusBuilder do
  def run_cli(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [stdout.string, stderr.string]
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

    stdout, = run_cli(['task', 'create', '--workflow', 'feature', '--title', title,
                       '--root', root.to_s, '--json'], cwd: root)
    JSON.parse(stdout).dig('task', 'id')
  end

  def force_done(root, task_id)
    task_path = Pathname.new(root) + 'tasks' + task_id + 'task.yaml'
    payload = YAML.safe_load(task_path.read, aliases: false, permitted_classes: [Time])
    payload['steps'].each { |s| s['status'] = 'done' }
    Owl::Tasks::Internal::AtomicYamlWriter.write(path: task_path, payload: payload)
  end

  def archive(root, title:, brief: nil)
    task_id = setup_project(root, title: title)
    write("#{root}/tasks/#{task_id}/brief.md", brief) if brief
    force_done(root, task_id)
    Owl::Archive::Api.archive_task(root: root, task_id: task_id, now: Time.utc(2026, 5, 17, 12, 0, 0))
    task_id
  end

  it 'builds documents only from archived tasks, excluding active ones' do
    with_tmp_project do |root|
      archived_id = archive(root, title: 'Archived feature',
                                  brief: "# Problem\nclosed work\n# Goal\ndone\n")
      active_id = setup_project(root, title: 'Active feature')

      corpus = described_class.build(root: root)
      ids = corpus.map { |doc| doc[:task_id] }

      expect(ids).to include(archived_id)
      expect(ids).not_to include(active_id)
    end
  end

  it 'reads the corpus through Owl::Archive::Api, not direct File.read' do
    with_tmp_project do |root|
      archive(root, title: 'Through the gateway', brief: "# Problem\np\n# Goal\ng\n")

      allow(Owl::Archive::Api).to receive(:list).and_call_original
      allow(Owl::Archive::Api).to receive(:read).and_call_original

      corpus = described_class.build(root: root)

      expect(corpus).not_to be_empty
      expect(Owl::Archive::Api).to have_received(:list).with(root: root)
      expect(Owl::Archive::Api).to have_received(:read).at_least(:once)
    end
  end

  it 'includes only Problem/Goal prose in the document text, not other sections' do
    with_tmp_project do |root|
      brief = <<~MD
        # Problem
        recall corpus problem prose
        # Goal
        recall corpus goal prose
        # Scenarios
        scenario-only-token
      MD
      archive(root, title: 'Sectioned', brief: brief)

      doc = described_class.build(root: root).first
      expect(doc[:text]).to include('problem')
      expect(doc[:text]).to include('goal')
      expect(doc[:text]).not_to include('scenario-only-token')
    end
  end

  it 'falls back to the title when an archived task has no brief' do
    with_tmp_project do |root|
      archive(root, title: 'No Brief Task', brief: nil)

      doc = described_class.build(root: root).first
      expect(doc[:title]).to eq('No Brief Task')
      expect(doc[:text]).to eq('No Brief Task')
    end
  end

  it 'returns [] when the archive role cannot be resolved' do
    with_tmp_project do |root|
      expect(described_class.build(root: "#{root}/missing")).to eq([])
    end
  end

  it 'tags archived documents with scope: archived' do
    with_tmp_project do |root|
      archive(root, title: 'Archived', brief: "# Problem\np\n# Goal\ng\n")

      doc = described_class.build(root: root, scope: 'archive').first
      expect(doc[:scope]).to eq('archived')
    end
  end

  it 'builds active documents from active task briefs, tagged scope: active' do
    with_tmp_project do |root|
      archive(root, title: 'Archived feature', brief: "# Problem\narchived\n# Goal\ndone\n")
      active_id = setup_project(root, title: 'Active feature')
      write("#{root}/tasks/#{active_id}/brief.md", "# Problem\nactive brief corpus token\n# Goal\ng\n")

      corpus = described_class.build(root: root, scope: 'active')
      doc = corpus.find { |d| d[:task_id] == active_id }

      expect(corpus.map { |d| d[:task_id] }).to eq([active_id])
      expect(doc[:scope]).to eq('active')
      expect(doc[:text]).to include('active brief corpus token')
    end
  end

  it 'reads active briefs through the tasks + artifact/storage layer, not direct File.read' do
    with_tmp_project do |root|
      active_id = setup_project(root, title: 'Active feature')
      write("#{root}/tasks/#{active_id}/brief.md", "# Problem\nlayered read\n# Goal\ng\n")

      allow(Owl::Tasks::Api).to receive(:list).and_call_original
      allow(Owl::Artifacts::Api).to receive(:resolve).and_call_original
      allow(Owl::Storage::Api).to receive(:read).and_call_original

      described_class.build(root: root, scope: 'active')

      expect(Owl::Tasks::Api).to have_received(:list).with(root: root)
      expect(Owl::Artifacts::Api).to have_received(:resolve)
        .with(root: root, task_id: active_id, artifact_key: 'brief')
      expect(Owl::Storage::Api).to have_received(:read).at_least(:once)
    end
  end

  it 'falls back to the title when an active task has no brief' do
    with_tmp_project do |root|
      active_id = setup_project(root, title: 'No Active Brief')

      doc = described_class.build(root: root, scope: 'active').find { |d| d[:task_id] == active_id }
      expect(doc[:text]).to eq('No Active Brief')
    end
  end

  it 'unions active and archived under scope all' do
    with_tmp_project do |root|
      archived_id = archive(root, title: 'Archived', brief: "# Problem\na\n# Goal\nb\n")
      active_id = setup_project(root, title: 'Active')

      ids = described_class.build(root: root, scope: 'all').map { |d| d[:task_id] }
      expect(ids).to contain_exactly(active_id, archived_id)
    end
  end

  it 'returns [] for an unrecognised scope' do
    with_tmp_project do |root|
      expect(described_class.build(root: root, scope: 'bogus')).to eq([])
    end
  end
end
