# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'

RSpec.describe 'owl overview CLI' do
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
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/composite_feature/workflow.yaml", <<~YAML)
      id: composite_feature
      kind: composite_task
      steps:
        - id: decompose
        - id: done_step
          requires: [decompose]
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
      id: feature
      kind: task
      steps:
        - id: brief
        - id: do
          requires: [brief]
    YAML
  end

  def create(root, title:, workflow: 'feature', parent: nil)
    argv = ['task', 'create', '--workflow', workflow, '--title', title, '--root', root.to_s]
    argv += ['--parent', parent] if parent
    run(argv, cwd: root)
  end

  describe 'empty forest' do
    it 'prints the "no planned tasks" message, not a blank line or error' do
      with_tmp_project do |root|
        init_with_workflows(root)
        exit_code, stdout, = run(['overview', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(0)
        expect(stdout).to include('нет запланированных задач')
      end
    end
  end

  describe 'forest with hierarchy' do
    it 'renders parent and child with tree connectors and status markers' do
      with_tmp_project do |root|
        init_with_workflows(root)
        create(root, title: 'Parent', workflow: 'composite_feature')
        create(root, title: 'Child', parent: 'TASK-0001')

        exit_code, stdout, = run(['overview', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(0)
        expect(stdout).to include('TASK-0001')
        expect(stdout).to include('TASK-0002')
        expect(stdout).to include('└─') # child connector
        expect(stdout).to include('[ ]') # pending marker (open task)
        expect(stdout).to include('workflow: feature')
      end
    end
  end

  describe 'subtree by TASK-ID' do
    it 'renders only the named task subtree' do
      with_tmp_project do |root|
        init_with_workflows(root)
        create(root, title: 'Parent', workflow: 'composite_feature')
        create(root, title: 'Child', parent: 'TASK-0001')
        create(root, title: 'Unrelated')

        exit_code, stdout, = run(['overview', 'TASK-0001', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(0)
        expect(stdout).to include('TASK-0001')
        expect(stdout).to include('TASK-0002')
        expect(stdout).not_to include('TASK-0003')
      end
    end
  end

  describe '--compact' do
    it 'omits the workflow key and progress bar' do
      with_tmp_project do |root|
        init_with_workflows(root)
        create(root, title: 'Solo')

        _exit, rich, = run(['overview', '--root', root.to_s], cwd: root)
        expect(rich).to include('workflow: feature')

        exit_code, compact, = run(['overview', '--compact', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(0)
        expect(compact).to include('TASK-0001')
        expect(compact).not_to include('workflow:')
        expect(compact).not_to include('·') # no progress-bar glyph
      end
    end
  end

  describe 'current-task highlight' do
    it 'marks the current task with ◀ текущая' do
      with_tmp_project do |root|
        init_with_workflows(root)
        create(root, title: 'A')
        create(root, title: 'B')
        run(['task', 'use', 'TASK-0002', '--root', root.to_s], cwd: root)

        _exit, stdout, = run(['overview', '--root', root.to_s], cwd: root)
        line = stdout.lines.find { |l| l.include?('TASK-0002') }
        expect(line).to include('◀ текущая')
        other = stdout.lines.find { |l| l.include?('TASK-0001') }
        expect(other).not_to include('◀ текущая')
      end
    end

    it 'does not crash and shows no highlight when the current pointer is broken' do
      with_tmp_project do |root|
        init_with_workflows(root)
        create(root, title: 'A')
        write("#{root}/.owl/local/current.yaml", "task_id: TASK-9999\n")

        exit_code, stdout, = run(['overview', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(0)
        expect(stdout).not_to include('◀ текущая')
      end
    end
  end

  describe 'inline dependencies' do
    it 'annotates a task with an unmet dependency and clears it once the dep completes' do
      with_tmp_project do |root|
        init_with_workflows(root)
        create(root, title: 'Dep')
        create(root, title: 'Dependent')
        run(['task', 'dep', 'add', 'TASK-0002', '--on', 'TASK-0001', '--root', root.to_s], cwd: root)

        _exit, blocked, = run(['overview', '--root', root.to_s], cwd: root)
        dependent_line = blocked.lines.find { |l| l.include?('TASK-0002') }
        expect(dependent_line).to include('⛔ ждёт TASK-0001')

        run(['task', 'set-status', 'TASK-0001', 'done', '--root', root.to_s], cwd: root)
        _exit, cleared, = run(['overview', '--root', root.to_s], cwd: root)
        cleared_line = cleared.lines.find { |l| l.include?('TASK-0002') }
        expect(cleared_line).not_to include('⛔')
      end
    end
  end

  describe '--all' do
    it 'hides abandoned tasks by default and includes them with --all' do
      with_tmp_project do |root|
        init_with_workflows(root)
        create(root, title: 'Live')
        create(root, title: 'Dead')
        run(['task', 'abandon', 'TASK-0002', '--root', root.to_s], cwd: root)

        _exit, default_out, = run(['overview', '--root', root.to_s], cwd: root)
        expect(default_out).to include('TASK-0001')
        expect(default_out).not_to include('TASK-0002')

        exit_code, all_out, = run(['overview', '--all', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(0)
        expect(all_out).to include('TASK-0002')
      end
    end
  end

  describe '--json' do
    it 'returns the structured tree contract instead of ASCII' do
      with_tmp_project do |root|
        init_with_workflows(root)
        create(root, title: 'Parent', workflow: 'composite_feature')
        create(root, title: 'Child', parent: 'TASK-0001')
        run(['task', 'use', 'TASK-0001', '--root', root.to_s], cwd: root)

        exit_code, stdout, = run(['overview', '--json', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['current_task_id']).to eq('TASK-0001')
        expect(body['warnings']).to eq([])
        root_node = body['tree'].first
        expect(root_node['id']).to eq('TASK-0001')
        expect(root_node).to include(
          'title', 'workflow_key', 'kind', 'status', 'parent_id',
          'progress', 'current', 'blocked_by', 'unmet_deps', 'children'
        )
        expect(root_node['progress']).to include('done', 'total', 'pct')
        expect(root_node['current']).to be(true)
        expect(root_node['children'].first['id']).to eq('TASK-0002')
      end
    end
  end

  describe 'unknown TASK-ID' do
    it 'returns a structured error, not a traceback' do
      with_tmp_project do |root|
        init_with_workflows(root)
        exit_code, _stdout, stderr = run(['overview', 'NOPE-1', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        body = JSON.parse(stderr)
        expect(body['ok']).to be(false)
        expect(body['error']['code']).to eq('task_not_found')
      end
    end
  end

  describe 'parent_id cycle' do
    it 'surfaces a tree_cycle warning without looping forever' do
      with_tmp_project do |root|
        init_with_workflows(root)
        create(root, title: 'A')
        create(root, title: 'B')

        # Hand-craft a parent_id cycle in the index (A ↔ B) — preserves all
        # existing fields, only rewrites parent_id.
        index_path = "#{root}/tasks/index.yaml"
        index = YAML.safe_load_file(index_path)
        index['tasks'].each do |entry|
          entry['parent_id'] = entry['id'] == 'TASK-0001' ? 'TASK-0002' : 'TASK-0001'
        end
        File.write(index_path, YAML.dump(index))

        exit_code, stdout, = run(['overview', 'TASK-0001', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(0)
        expect(stdout).to include('tree_cycle')

        exit_code_json, json_out, = run(['overview', 'TASK-0001', '--json', '--root', root.to_s], cwd: root)
        expect(exit_code_json).to eq(0)
        warnings = JSON.parse(json_out)['warnings']
        expect(warnings.map { |w| w['code'] }).to include('tree_cycle')
      end
    end
  end
end
