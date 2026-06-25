# frozen_string_literal: true

require 'stringio'

require 'owl/cli/api'
require 'owl/result'
require 'owl/tasks/api'
require 'owl/tasks/internal/availability_scanner'
require 'owl/workflows/api'

RSpec.describe Owl::Tasks::Internal::AvailabilityScanner do
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
  end

  def stub_ready_steps(ready:, conditional_skip:)
    allow(Owl::Workflows::Api).to receive(:ready_steps).and_return(
      Owl::Result.ok(ready: ready, conditional_skip: conditional_skip)
    )
  end

  def available_ids(root)
    described_class.scan(root: root).value[:available].map { |c| c[:task_id] }
  end

  it 'includes a task whose only actionable step is a conditional_skip step' do
    with_tmp_project do |root|
      setup_project(root)
      # No dispatchable `ready` step, but a false-`when:` step sits in
      # conditional_skip — the orchestrator can still advance it via skip.
      stub_ready_steps(ready: [], conditional_skip: [{ id: 'design', reason: 'condition_unmet' }])
      candidate = described_class.scan(root: root).value[:available].first
      expect(candidate[:task_id]).to eq('TASK-0001')
      expect(candidate[:ready_step_ids]).to eq(['design'])
    end
  end

  it 'excludes a task with neither ready nor conditional_skip steps' do
    with_tmp_project do |root|
      setup_project(root)
      stub_ready_steps(ready: [], conditional_skip: [])
      expect(available_ids(root)).to eq([])
    end
  end

  it 'keeps a task with a ready step available (regression) and carries it in ready_step_ids' do
    with_tmp_project do |root|
      setup_project(root)
      stub_ready_steps(ready: [{ id: 'a' }], conditional_skip: [])
      candidate = described_class.scan(root: root).value[:available].first
      expect(candidate[:task_id]).to eq('TASK-0001')
      expect(candidate[:ready_step_ids]).to eq(['a'])
    end
  end

  it 'unions ready and conditional_skip step ids when both are present' do
    with_tmp_project do |root|
      setup_project(root)
      stub_ready_steps(ready: [{ id: 'a' }], conditional_skip: [{ id: 'design' }])
      candidate = described_class.scan(root: root).value[:available].first
      expect(candidate[:ready_step_ids]).to eq(%w[a design])
    end
  end
end
