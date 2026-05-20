# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/status/api'

RSpec.describe Owl::Status::Api do
  def cli(argv, root)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def init_project(root)
    cli(['init', '--root', root.to_s], root)
  end

  def seed_two_step_feature(root)
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
          skill: owl-step-run
        - id: b
          skill: owl-step-run
          requires: ["a"]
      artifacts: []
    YAML
  end

  def seed_composite_and_slice(root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        composite_feature:
          enabled: true
          source: "workflows/composite_feature/workflow.yaml"
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/composite_feature/workflow.yaml", <<~YAML)
      id: composite_feature
      kind: composite_task
      steps:
        - id: spec
          skill: owl-step-run
      artifacts: []
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
      id: feature
      kind: task
      steps:
        - id: do
          skill: owl-step-run
      artifacts: []
    YAML
  end

  describe '.show' do
    it 'returns task header, steps with ready flag, progress and empty blockers for a single task' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_feature(root)
        cli(['task', 'create', '--workflow', 'feature', '--title', 'plain', '--root', root.to_s], root)
        cli(['step', 'start', 'TASK-0001', 'a', '--root', root.to_s], root)
        cli(['step', 'complete', 'TASK-0001', 'a', '--root', root.to_s], root)

        result = described_class.show(root: root, task_id: 'TASK-0001')

        expect(result).to be_ok
        body = result.value
        expect(body[:ok]).to be(true)
        expect(body.dig(:task, :id)).to eq('TASK-0001')
        expect(body.dig(:task, :workflow_key)).to eq('feature')
        expect(body[:steps].map { |s| [s[:id], s[:status], s[:ready]] }).to eq([
                                                                                 ['a', 'done', false],
                                                                                 ['b', 'pending', true]
                                                                               ])
        expect(body[:progress]).to eq(done: 1, total: 2, pct: 50.0)
        expect(body[:blockers]).to eq([])
        expect(body).not_to have_key(:children)
      end
    end

    it 'falls back to the current task pointer when task_id is not supplied' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_feature(root)
        cli(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s], root)
        cli(['task', 'use', 'TASK-0001', '--root', root.to_s], root)

        result = described_class.show(root: root)

        expect(result).to be_ok
        expect(result.value.dig(:task, :id)).to eq('TASK-0001')
      end
    end

    it 'includes a children array with progress for each child of a composite task' do
      with_tmp_project do |root|
        init_project(root)
        seed_composite_and_slice(root)
        cli(['task', 'create', '--workflow', 'composite_feature', '--title', 'parent',
             '--root', root.to_s], root)
        cli(['task', 'child', 'create', 'TASK-0001', '--workflow', 'feature', '--title', 'child a',
             '--root', root.to_s], root)
        cli(['task', 'child', 'create', 'TASK-0001', '--workflow', 'feature', '--title', 'child b',
             '--root', root.to_s], root)
        cli(['step', 'start', 'TASK-0002', 'do', '--root', root.to_s], root)
        cli(['step', 'complete', 'TASK-0002', 'do', '--root', root.to_s], root)

        result = described_class.show(root: root, task_id: 'TASK-0001')

        expect(result).to be_ok
        children = result.value[:children]
        expect(children).to be_an(Array)
        expect(children.size).to eq(2)
        completed = children.find { |c| c[:id] == 'TASK-0002' }
        expect(completed[:progress]).to eq(done: 1, total: 1, pct: 100.0)
      end
    end

    it 'returns children: [] when a composite task has no children' do
      with_tmp_project do |root|
        init_project(root)
        seed_composite_and_slice(root)
        cli(['task', 'create', '--workflow', 'composite_feature', '--title', 'parent',
             '--root', root.to_s], root)

        result = described_class.show(root: root, task_id: 'TASK-0001')

        expect(result).to be_ok
        expect(result.value[:children]).to eq([])
      end
    end

    it 'lists steps with blocked or failed status in the blockers field' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_feature(root)
        cli(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s], root)
        task_path = "#{root}/tasks/TASK-0001/task.yaml"
        task_yaml = YAML.safe_load_file(task_path)
        task_yaml['steps'][0]['status'] = 'blocked'
        task_yaml['steps'][1]['status'] = 'failed'
        File.write(task_path, task_yaml.to_yaml)

        result = described_class.show(root: root, task_id: 'TASK-0001')

        expect(result).to be_ok
        expect(result.value[:blockers].map { |b| [b[:id], b[:status]] }).to contain_exactly(
          %w[a blocked],
          %w[b failed]
        )
      end
    end

    it 'returns :no_current_task when the pointer is empty and no task_id is supplied' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_feature(root)

        result = described_class.show(root: root)

        expect(result).to be_err
        expect(result.code).to eq(:no_current_task)
      end
    end

    it 'returns :task_not_found for an unknown task id' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_feature(root)

        result = described_class.show(root: root, task_id: 'TASK-9999')

        expect(result).to be_err
        expect(result.code).to eq(:task_not_found)
      end
    end
  end
end
