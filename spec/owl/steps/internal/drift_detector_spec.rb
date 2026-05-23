# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'
require 'owl/steps/api'
require 'owl/steps/internal/drift_detector'

RSpec.describe Owl::Steps::Internal::DriftDetector do
  def run_cli(argv, cwd:)
    Owl::Cli::Api.run(
      argv: argv, stdout: StringIO.new, stderr: StringIO.new, env: {}, cwd: cwd.to_s
    )
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
    write("#{root}/.owl/artifacts.yaml", <<~YAML)
      schema_version: 1
      artifacts:
        brief:
          source: "artifacts/brief/artifact.yaml"
    YAML
    write("#{root}/.owl/artifacts/brief/artifact.yaml", "id: brief\nkind: markdown\n")
    write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
      id: feature
      kind: task
      artifacts:
        brief:
          type: brief
          storage:
            role: tasks
            path: "{{task.id}}/brief.md"
      steps:
        - id: a
          creates: [brief]
    YAML
    stdout = StringIO.new
    Owl::Cli::Api.run(
      argv: ['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s, '--json'],
      stdout: stdout, stderr: StringIO.new, env: {}, cwd: root.to_s
    )
    JSON.parse(stdout.string).dig('task', 'id')
  end

  def complete_step(root, task_id, body: "# original\n")
    write("#{root}/tasks/#{task_id}/brief.md", body)
    Owl::Steps::Api.start(root: root, task_id: task_id, step_id: 'a')
    Owl::Steps::Api.complete(root: root, task_id: task_id, step_id: 'a')
  end

  describe '.call' do
    it 'returns an empty list when content_sha has never been recorded' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        expect(described_class.call(root: root, task_id: task_id, step_id: 'a')).to eq([])
      end
    end

    it 'returns an empty list when the file has not changed since complete' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        complete_step(root, task_id)
        expect(described_class.call(root: root, task_id: task_id, step_id: 'a')).to eq([])
      end
    end

    it 'returns a :modified event when the file content changed' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        complete_step(root, task_id)
        write("#{root}/tasks/#{task_id}/brief.md", "# tampered\n")

        events = described_class.call(root: root, task_id: task_id, step_id: 'a')
        expect(events.size).to eq(1)
        expect(events.first[:type]).to eq(:modified)
        expect(events.first[:step_id]).to eq('a')
        expect(events.first[:artifact_key]).to eq('brief')
        expect(events.first[:recorded_sha]).not_to eq(events.first[:actual_sha])
      end
    end

    it 'returns a :missing event when the artifact file has been deleted' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        complete_step(root, task_id)
        File.delete("#{root}/tasks/#{task_id}/brief.md")

        events = described_class.call(root: root, task_id: task_id, step_id: 'a')
        expect(events.size).to eq(1)
        expect(events.first[:type]).to eq(:missing)
        expect(events.first[:artifact_key]).to eq('brief')
      end
    end

    it 'returns an empty list for an unknown step' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        expect(described_class.call(root: root, task_id: task_id, step_id: 'ghost')).to eq([])
      end
    end
  end
end
