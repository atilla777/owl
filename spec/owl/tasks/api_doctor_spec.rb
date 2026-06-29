# frozen_string_literal: true

require 'stringio'

require 'owl/cli/api'
require 'owl/tasks/api'

RSpec.describe 'Owl::Tasks::Api.lifecycle_drift' do
  def cli(argv, root)
    Owl::Cli::Api.run(argv: argv, stdout: StringIO.new, stderr: StringIO.new, env: {}, cwd: root.to_s)
  end

  def setup_project(root)
    cli(['init', '--root', root.to_s], root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        quick:
          enabled: true
          source: "workflows/quick/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/quick/workflow.yaml", <<~YAML)
      id: quick
      kind: task
      artifacts: {}
      steps:
        - id: build
    YAML
    cli(['task', 'create', '--workflow', 'quick', '--title', 't', '--root', root.to_s, '--json'], root)
  end

  it 'returns Result.ok with the drifted list for a workflow-complete open task' do
    with_tmp_project do |root|
      setup_project(root)
      cli(['step', 'start', 'TASK-0001', 'build', '--root', root.to_s, '--json'], root)
      cli(['step', 'complete', 'TASK-0001', 'build', '--root', root.to_s, '--json'], root)
      # Completing the terminal step auto-promotes to `done`; reopen to drift.
      cli(['task', 'set-status', 'TASK-0001', 'open', '--root', root.to_s, '--json'], root)

      result = Owl::Tasks::Api.lifecycle_drift(root: root)
      expect(result).to be_ok
      expect(result.value[:drifted].map { |d| d[:task_id] }).to eq(['TASK-0001'])
    end
  end

  it 'returns an empty drifted list when nothing is complete' do
    with_tmp_project do |root|
      setup_project(root)

      result = Owl::Tasks::Api.lifecycle_drift(root: root)
      expect(result).to be_ok
      expect(result.value[:drifted]).to be_empty
    end
  end
end
