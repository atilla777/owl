# frozen_string_literal: true

require 'stringio'

require 'owl/cli/api'
require 'owl/steps/api'

RSpec.describe 'Owl::Steps::Api status / mark_running' do
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
      kind: feature
      steps:
        - id: a
        - id: b
          requires: ["a"]
      artifacts: []
    YAML
    cli(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s, '--json'], root)
    'TASK-0001'
  end

  describe '.status' do
    it 'returns the current status string for a known step' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        result = Owl::Steps::Api.status(root: root, task_id: task_id, step_id: 'a')

        expect(result).to be_ok
        expect(result.value[:status]).to be_a(String)
      end
    end

    it 'returns nil status for an unknown step' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        result = Owl::Steps::Api.status(root: root, task_id: task_id, step_id: 'nope')

        expect(result).to be_ok
        expect(result.value[:status]).to be_nil
      end
    end
  end

  describe '.mark_running' do
    it 'forces a step to running and is observable via .status' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        result = Owl::Steps::Api.mark_running(root: root, task_id: task_id, step_id: 'a')

        expect(result).to be_ok
        expect(Owl::Steps::Api.status(root: root, task_id: task_id, step_id: 'a').value[:status]).to eq('running')
      end
    end

    it 'returns unknown_step_id for a step that does not exist' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        result = Owl::Steps::Api.mark_running(root: root, task_id: task_id, step_id: 'nope')

        expect(result).to be_err
        expect(result.code).to eq(:unknown_step_id)
      end
    end
  end
end
