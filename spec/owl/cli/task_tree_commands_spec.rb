# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'owl task tree-/children-/parent-/aggregate-status/child create/split CLI subcommands' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def init_with_workflows(root)
    run(['init', '--root', root.to_s], cwd: root)
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
    write("#{root}/.owl/workflows/composite_feature/workflow.yaml",
          "id: composite_feature\nkind: composite_task\nsteps:\n  - id: only\nartifacts: []\n")
    write("#{root}/.owl/workflows/feature_slice/workflow.yaml",
          "id: feature_slice\nkind: task\nsteps:\n  - id: do\nartifacts: []\n")
  end

  describe '--help' do
    it 'mentions the new task subcommands' do
      with_tmp_project do |root|
        _exit, _stdout, stderr = run(['--help'], cwd: root)
        expect(stderr).to include('task tree')
        expect(stderr).to include('task children')
        expect(stderr).to include('task parent')
        expect(stderr).to include('task aggregate-status')
        expect(stderr).to include('task child create')
        expect(stderr).to include('task split')
      end
    end
  end

  describe 'owl task tree' do
    it 'prints nested task tree as JSON' do
      with_tmp_project do |root|
        init_with_workflows(root)
        run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)
        run(
          ['task', 'create', '--workflow', 'feature_slice', '--title', 'C', '--parent', 'TASK-0001', '--root',
           root.to_s], cwd: root
        )

        exit_code, stdout, = run(['task', 'tree', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['tasks'].first['id']).to eq('TASK-0001')
        expect(body['tasks'].first['children'].first['id']).to eq('TASK-0002')
      end
    end
  end

  describe 'owl task children' do
    it 'prints children of a composite parent' do
      with_tmp_project do |root|
        init_with_workflows(root)
        run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)
        run(
          ['task', 'create', '--workflow', 'feature_slice', '--title', 'C', '--parent', 'TASK-0001', '--root',
           root.to_s], cwd: root
        )

        exit_code, stdout, = run(['task', 'children', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['children'].first['id']).to eq('TASK-0002')
      end
    end

    it 'fails when TASK-ID is missing' do
      with_tmp_project do |root|
        init_with_workflows(root)
        exit_code, _stdout, stderr = run(['task', 'children', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'owl task parent' do
    it 'returns parent payload for a child' do
      with_tmp_project do |root|
        init_with_workflows(root)
        run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)
        run(
          ['task', 'create', '--workflow', 'feature_slice', '--title', 'C', '--parent', 'TASK-0001', '--root',
           root.to_s], cwd: root
        )

        exit_code, stdout, = run(['task', 'parent', 'TASK-0002', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        expect(JSON.parse(stdout).dig('parent', 'id')).to eq('TASK-0001')
      end
    end

    it 'returns parent: null for a top-level task' do
      with_tmp_project do |root|
        init_with_workflows(root)
        run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)
        exit_code, stdout, = run(['task', 'parent', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        expect(JSON.parse(stdout)['parent']).to be_nil
      end
    end
  end

  describe 'owl task aggregate-status' do
    it 'returns aggregate state for a composite parent' do
      with_tmp_project do |root|
        init_with_workflows(root)
        run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)
        run(
          ['task', 'create', '--workflow', 'feature_slice', '--title', 'C', '--parent', 'TASK-0001', '--root',
           root.to_s], cwd: root
        )

        exit_code, stdout, = run(['task', 'aggregate-status', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        expect(JSON.parse(stdout)['aggregate']).to eq('open')
      end
    end

    it 'fails for non-composite tasks' do
      with_tmp_project do |root|
        init_with_workflows(root)
        run(['task', 'create', '--workflow', 'feature_slice', '--title', 'plain', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(['task', 'aggregate-status', 'TASK-0001', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('not_a_composite_task')
      end
    end
  end

  describe 'owl task child create' do
    it 'creates a child under a composite parent' do
      with_tmp_project do |root|
        init_with_workflows(root)
        run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)

        exit_code, stdout, = run(
          ['task', 'child', 'create', 'TASK-0001', '--workflow', 'feature_slice', '--title', 'C', '--root', root.to_s,
           '--json'],
          cwd: root
        )
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['parent_id']).to eq('TASK-0001')
        expect(body.dig('task', 'id')).to eq('TASK-0002')
      end
    end

    it 'rejects parent that is not composite' do
      with_tmp_project do |root|
        init_with_workflows(root)
        run(['task', 'create', '--workflow', 'feature_slice', '--title', 'plain', '--root', root.to_s], cwd: root)

        exit_code, _stdout, stderr = run(
          ['task', 'child', 'create', 'TASK-0001', '--workflow', 'feature_slice', '--title', 'C', '--root', root.to_s],
          cwd: root
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('parent_not_composite')
      end
    end
  end

  describe 'owl task split' do
    it 'flips a task into composite_task' do
      with_tmp_project do |root|
        init_with_workflows(root)
        run(['task', 'create', '--workflow', 'feature_slice', '--title', 'T', '--root', root.to_s], cwd: root)

        exit_code, stdout, = run(['task', 'split', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['changed']).to be(true)
        expect(body['kind']).to eq('composite_task')
      end
    end
  end
end
