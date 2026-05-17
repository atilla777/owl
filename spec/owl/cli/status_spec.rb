# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'

RSpec.describe 'owl status CLI subcommand' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def init_project(root)
    run(['init', '--root', root.to_s], cwd: root)
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
          skill: owl-step-brief
        - id: b
          skill: owl-step-specify
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
        feature_slice:
          enabled: true
          source: "workflows/feature_slice/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/composite_feature/workflow.yaml", <<~YAML)
      id: composite_feature
      kind: composite_task
      steps:
        - id: spec
          skill: owl-step-specify
      artifacts: []
    YAML
    write("#{root}/.owl/workflows/feature_slice/workflow.yaml", <<~YAML)
      id: feature_slice
      kind: task
      steps:
        - id: do
          skill: owl-step-apply
      artifacts: []
    YAML
  end

  describe 'happy path' do
    it 'returns task header, steps with ready flag, progress and empty blockers' do # rubocop:disable RSpec/MultipleExpectations
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_feature(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 'plain', '--root', root.to_s], cwd: root)
        run(['step', 'start', 'TASK-0001', 'a', '--root', root.to_s], cwd: root)
        run(['step', 'complete', 'TASK-0001', 'a', '--root', root.to_s], cwd: root)

        exit_code, stdout, _stderr = run(['status', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body.dig('task', 'id')).to eq('TASK-0001')
        expect(body.dig('task', 'workflow_key')).to eq('feature')
        expect(body.dig('task', 'kind')).to eq('feature')
        expect(body['steps'].map { |s| [s['id'], s['status'], s['ready']] }).to eq([
                                                                                     ['a', 'done', false],
                                                                                     ['b', 'pending', true]
                                                                                   ])
        expect(body.dig('progress', 'done')).to eq(1)
        expect(body.dig('progress', 'total')).to eq(2)
        expect(body.dig('progress', 'pct')).to eq(50.0)
        expect(body['blockers']).to eq([])
        expect(body).not_to have_key('children')
      end
    end

    it 'resolves task from current pointer when no positional id is passed' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_feature(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s], cwd: root)
        run(['task', 'use', 'TASK-0001', '--root', root.to_s], cwd: root)

        exit_code, stdout, _stderr = run(['status', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        expect(JSON.parse(stdout).dig('task', 'id')).to eq('TASK-0001')
      end
    end
  end

  describe 'composite tasks' do
    it 'includes a children array with progress for each child' do
      with_tmp_project do |root|
        init_project(root)
        seed_composite_and_slice(root)
        run(['task', 'create', '--workflow', 'composite_feature', '--title', 'parent', '--root', root.to_s], cwd: root)
        slice = ['task', 'create', '--workflow', 'feature_slice']
        run([*slice, '--title', 'c1', '--parent', 'TASK-0001', '--root', root.to_s], cwd: root)
        run([*slice, '--title', 'c2', '--parent', 'TASK-0001', '--root', root.to_s], cwd: root)
        run(['step', 'start', 'TASK-0002', 'do', '--root', root.to_s], cwd: root)
        run(['step', 'complete', 'TASK-0002', 'do', '--root', root.to_s], cwd: root)

        exit_code, stdout, _stderr = run(['status', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body.dig('task', 'kind')).to eq('composite_task')
        children = body['children']
        expect(children.map { |c| c['id'] }).to contain_exactly('TASK-0002', 'TASK-0003')
        c1 = children.find { |c| c['id'] == 'TASK-0002' }
        c2 = children.find { |c| c['id'] == 'TASK-0003' }
        expect(c1.dig('progress', 'done')).to eq(1)
        expect(c1.dig('progress', 'total')).to eq(1)
        expect(c1.dig('progress', 'pct')).to eq(100.0)
        expect(c2.dig('progress', 'done')).to eq(0)
        expect(c2.dig('progress', 'total')).to eq(1)
      end
    end

    it 'returns children: [] when a composite task has no children' do
      with_tmp_project do |root|
        init_project(root)
        seed_composite_and_slice(root)
        run(['task', 'create', '--workflow', 'composite_feature', '--title', 'lonely', '--root', root.to_s], cwd: root)

        exit_code, stdout, _stderr = run(['status', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['children']).to eq([])
      end
    end
  end

  describe 'blockers' do
    it 'lists steps with blocked or failed status' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_feature(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 'stuck', '--root', root.to_s], cwd: root)
        task_path = root + 'tasks/TASK-0001/task.yaml'
        payload = YAML.safe_load(task_path.read, aliases: false, permitted_classes: [Time])
        payload['steps'].first['status'] = 'blocked'
        task_path.write(YAML.dump(payload))

        exit_code, stdout, _stderr = run(['status', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['blockers']).to eq([{ 'id' => 'a', 'status' => 'blocked' }])
      end
    end
  end

  describe 'error paths' do
    it 'fails with no_current_task when pointer is empty and no positional task id' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_feature(root)
        exit_code, _stdout, stderr = run(['status', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('no_current_task')
      end
    end

    it 'fails with task_not_found for an unknown task id' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_feature(root)
        exit_code, _stdout, stderr = run(['status', 'TASK-9999', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('task_not_found')
      end
    end
  end
end
