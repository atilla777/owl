# frozen_string_literal: true

require 'stringio'

require 'owl/cli/api'
require 'owl/tasks/api'

RSpec.describe Owl::Tasks::Api, '.orchestration_terminal?' do
  def cli(argv, root)
    Owl::Cli::Api.run(argv: argv, stdout: StringIO.new, stderr: StringIO.new, env: {}, cwd: root.to_s)
  end

  def setup_project(root)
    cli(['init', '--root', root.to_s], root)
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
      artifacts: {}
      steps:
        - id: a
    YAML
    cli(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s, '--json'], root)
    'TASK-0001'
  end

  it 'is false for a live (open) task' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      result = described_class.orchestration_terminal?(root: root, task_id: task_id)
      expect(result).to be_ok
      expect(result.value).to be(false)
    end
  end

  it 'is true for an abandoned task even with a still-ready step (the leak bug)' do
    with_tmp_project do |root|
      task_id = setup_project(root)
      described_class.abandon(root: root, task_id: task_id)
      result = described_class.orchestration_terminal?(root: root, task_id: task_id)
      expect(result.value).to be(true)
    end
  end

  it 'propagates the underlying Err for an unknown task' do
    with_tmp_project do |root|
      setup_project(root)
      result = described_class.orchestration_terminal?(root: root, task_id: 'TASK-9999')
      expect(result).to be_err
      expect(result.code).to eq(:task_not_found)
    end
  end
end
