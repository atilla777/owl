# frozen_string_literal: true

require 'stringio'

require 'owl/cli/api'
require 'owl/tasks/api'
require 'owl/tasks/internal/ready_availability_scanner'

RSpec.describe Owl::Tasks::Internal::ReadyAvailabilityScanner do
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
  end

  def create_task(root, title: 't')
    cli(['task', 'create', '--workflow', 'feature', '--title', title, '--root', root.to_s, '--json'], root)
  end

  def scan_ids(root)
    described_class.scan(root: root).value[:available].map { |c| c['task_id'] }
  end

  it 'includes a normal task with its ready_step_ids and reason intact' do
    with_tmp_project do |root|
      setup_project(root)
      create_task(root, title: 'normal')
      candidate = described_class.scan(root: root).value[:available].first
      expect(candidate['task_id']).to eq('TASK-0001')
      expect(candidate['ready_step_ids']).to eq(['a'])
      expect(candidate['reason']).to be_a(String)
    end
  end

  it 'excludes a task with no ready workflow step (available filter preserved)' do
    with_tmp_project do |root|
      setup_project(root)
      # A workflow with zero steps yields no ready step → not available.
      write("#{root}/.owl/workflows/empty/workflow.yaml", <<~YAML)
        id: empty
        kind: task
        artifacts: {}
        steps: []
      YAML
      write("#{root}/.owl/workflows.yaml", <<~YAML)
        schema_version: 1
        workflows:
          feature:
            enabled: true
            source: "workflows/feature/workflow.yaml"
          empty:
            enabled: true
            source: "workflows/empty/workflow.yaml"
      YAML
      create_task(root, title: 'has-step')
      cli(['task', 'create', '--workflow', 'empty', '--title', 'no-step', '--root', root.to_s, '--json'], root)
      expect(scan_ids(root)).to eq(['TASK-0001'])
    end
  end

  it 'excludes a dep-blocked task while its dependency is unfinished' do
    with_tmp_project do |root|
      setup_project(root)
      create_task(root, title: 'dep')
      create_task(root, title: 'blocked')
      Owl::Tasks::Api.add_dependency(root: root, task_id: 'TASK-0002', depends_on: 'TASK-0001')
      ids = scan_ids(root)
      expect(ids).to include('TASK-0001')
      expect(ids).not_to include('TASK-0002')
    end
  end

  it 'excludes an on_hold task' do
    with_tmp_project do |root|
      setup_project(root)
      create_task(root, title: 'parked')
      create_task(root, title: 'live')
      Owl::Tasks::Api.set_status(root: root, task_id: 'TASK-0001', status: 'on_hold')
      ids = scan_ids(root)
      expect(ids).not_to include('TASK-0001')
      expect(ids).to include('TASK-0002')
    end
  end

  it 'propagates an error when resolution fails' do
    with_tmp_project do |root|
      result = described_class.scan(root: root)
      expect(result).to be_err
    end
  end
end
