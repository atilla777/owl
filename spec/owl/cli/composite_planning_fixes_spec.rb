# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'

# Regression coverage for the CLI/workflow warts surfaced while planning a
# composite task in a consumer project (parent + 9 children over `owl --json`
# only): non-atomic `child create --brief-body`, orphan children on parent
# delete, missing `dep remove`, unreachable nested-group help, the wrong
# `--parent` child-create syntax in the docs, `task tree` ignoring its TASK-ID,
# and doctor blind to referential-integrity drift.
RSpec.describe 'composite planning CLI fixes' do
  def run(argv, cwd:, stdin: nil)
    stdout = StringIO.new
    stderr = StringIO.new
    with_stdin(stdin) do
      exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
      [exit_code, stdout.string, stderr.string]
    end
  end

  def with_stdin(content)
    return yield if content.nil?

    original = $stdin
    $stdin = StringIO.new(content)
    yield
  ensure
    $stdin = original if content
  end

  def init_composite(root)
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
      allowed_children: [feature]
      artifacts:
        brief:
          type: brief
          storage:
            role: tasks
            path: "{{task.id}}/brief.md"
      steps:
        - id: only
    YAML
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
        - id: brief
          creates: [brief]
        - id: do
          requires: [brief]
    YAML
  end

  def parent_and_children(root, child_count)
    init_composite(root)
    run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)
    child_count.times do |i|
      run(['task', 'child', 'create', 'TASK-0001', '--workflow', 'feature',
           '--title', "C#{i}", '--root', root.to_s], cwd: root)
    end
  end

  describe 'atomic child create (problem 1 + 8)' do
    it 'rolls back so a rejected --brief-body reuses the same id next time' do
      with_tmp_project do |root|
        init_composite(root)
        run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)

        exit_code, _out, err = run(
          ['task', 'child', 'create', 'TASK-0001', '--workflow', 'feature', '--title', 'C',
           '--brief-body', '-', '--root', root.to_s],
          cwd: root, stdin: "garbage\n"
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(err).dig('error', 'details', 'rolled_back')).to be(true)
        expect((root + 'tasks/TASK-0002').exist?).to be(false)

        # The rolled-back id is free, so a subsequent create is TASK-0002 again.
        _e, out, = run(['task', 'child', 'create', 'TASK-0001', '--workflow', 'feature',
                        '--title', 'C', '--root', root.to_s, '--json'], cwd: root)
        expect(JSON.parse(out).dig('task', 'id')).to eq('TASK-0002')
      end
    end
  end

  describe 'recursive delete (problem 2)' do
    it 'refuses to orphan children without --recursive and lists them' do
      with_tmp_project do |root|
        parent_and_children(root, 2)

        exit_code, _out, err = run(['task', 'delete', 'TASK-0001', '--force', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        # stderr carries the irreversible-delete WARNING line + the JSON envelope;
        # machine consumers read the line that starts the JSON object.
        payload = JSON.parse(err.lines.find { |l| l.start_with?('{') })
        expect(payload.dig('error', 'code')).to eq('task_has_children')
        expect(payload.dig('error', 'details', 'children')).to contain_exactly('TASK-0002', 'TASK-0003')
        # Nothing was removed.
        expect((root + 'tasks/TASK-0001').exist?).to be(true)
        expect((root + 'tasks/TASK-0002').exist?).to be(true)
      end
    end

    it 'removes the full subtree with --recursive and rebuilds the index' do
      with_tmp_project do |root|
        parent_and_children(root, 2)

        exit_code, out, = run(['task', 'delete', 'TASK-0001', '--force', '--recursive',
                               '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(0)
        expect(JSON.parse(out)['removed_task_ids']).to contain_exactly('TASK-0001', 'TASK-0002', 'TASK-0003')
        expect((root + 'tasks/TASK-0001').exist?).to be(false)
        expect((root + 'tasks/TASK-0002').exist?).to be(false)
        index = YAML.safe_load((root + 'tasks/index.yaml').read, aliases: false, permitted_classes: [Time])
        expect(Array(index['tasks'])).to be_empty
      end
    end

    it 'still deletes a childless task without --recursive' do
      with_tmp_project do |root|
        init_composite(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 'plain', '--root', root.to_s], cwd: root)
        exit_code, out, = run(['task', 'delete', 'TASK-0001', '--force', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(0)
        expect(JSON.parse(out)['removed']).to be(true)
      end
    end
  end

  describe 'dep remove + list (problem 3)' do
    it 'adds, lists, and removes a blocked_by edge without editing files' do
      with_tmp_project do |root|
        parent_and_children(root, 2)

        run(['task', 'dep', 'add', 'TASK-0003', '--on', 'TASK-0002', '--root', root.to_s], cwd: root)
        _e, out, = run(['task', 'dep', 'list', 'TASK-0003', '--root', root.to_s], cwd: root)
        expect(JSON.parse(out)['blocked_by']).to eq(['TASK-0002'])

        # `remove` is accepted as an alias for `rm`.
        exit_code, out, = run(['task', 'dep', 'remove', 'TASK-0003', '--on', 'TASK-0002', '--root', root.to_s],
                              cwd: root)
        expect(exit_code).to eq(0)
        expect(JSON.parse(out)['blocked_by']).to eq([])
      end
    end

    it 'is idempotent: duplicate add does not duplicate, remove of absent is a no-op' do
      with_tmp_project do |root|
        parent_and_children(root, 2)

        run(['task', 'dep', 'add', 'TASK-0003', '--on', 'TASK-0002', '--root', root.to_s], cwd: root)
        _e, out, = run(['task', 'dep', 'add', 'TASK-0003', '--on', 'TASK-0002', '--root', root.to_s], cwd: root)
        expect(JSON.parse(out)['blocked_by']).to eq(['TASK-0002'])

        exit_code, out, = run(['task', 'dep', 'rm', 'TASK-0003', '--on', 'TASK-0999', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(0)
        expect(JSON.parse(out)['blocked_by']).to eq(['TASK-0002'])
      end
    end
  end

  describe 'reachable nested-group help (problem 4)' do
    it 'owl task dep --help lists subcommands (exit 0)' do
      with_tmp_project do |root|
        exit_code, _out, err = run(['task', 'dep', '--help'], cwd: root)
        expect(exit_code).to eq(0)
        expect(err).to include('add', 'rm', 'remove', 'list')
      end
    end

    it 'owl task dep --json returns a structured subcommand listing' do
      with_tmp_project do |root|
        _e, out, = run(['task', 'dep', '--json'], cwd: root)
        body = JSON.parse(out)
        expect(body['command']).to eq('task dep')
        expect(body['subcommands']).to include('remove')
      end
    end

    it 'owl task dep (bare) returns missing_subcommand, not unknown_command' do
      with_tmp_project do |root|
        exit_code, _out, err = run(%w[task dep], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(err).dig('error', 'code')).to eq('missing_subcommand')
      end
    end

    it 'owl task label / child / index --help are all reachable' do
      with_tmp_project do |root|
        %w[label child index].each do |group|
          exit_code, _out, err = run(['task', group, '--help'], cwd: root)
          expect(exit_code).to eq(0)
          expect(err).to include('Subcommands:')
        end
      end
    end
  end

  describe 'documented --parent child-create syntax (problem 5)' do
    it 'accepts --parent PARENT-ID as an alias for the positional parent id' do
      with_tmp_project do |root|
        init_composite(root)
        run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)

        exit_code, out, = run(['task', 'child', 'create', '--parent', 'TASK-0001',
                               '--workflow', 'feature', '--title', 'C', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(out)
        expect(body['parent_id']).to eq('TASK-0001')
        expect(body.dig('task', 'id')).to eq('TASK-0002')
      end
    end
  end

  describe 'task tree TASK-ID returns only the subtree (problem 6)' do
    it 'scopes the response to the named task, excluding unrelated top-level tasks' do
      with_tmp_project do |root|
        init_composite(root)
        # Two unrelated top-level composites, second gets a child.
        run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P1', '--root', root.to_s], cwd: root)
        run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P2', '--root', root.to_s], cwd: root)
        run(['task', 'child', 'create', 'TASK-0002', '--workflow', 'feature',
             '--title', 'C', '--root', root.to_s], cwd: root)

        exit_code, out, = run(['task', 'tree', 'TASK-0002', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(out)
        expect(body['tasks'].map { |t| t['id'] }).to eq(['TASK-0002'])
        expect(body['tasks'].first['children'].map { |c| c['id'] }).to eq(['TASK-0003'])
      end
    end

    it 'still returns the full forest when no TASK-ID is given' do
      with_tmp_project do |root|
        init_composite(root)
        run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P1', '--root', root.to_s], cwd: root)
        run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P2', '--root', root.to_s], cwd: root)

        _e, out, = run(['task', 'tree', '--root', root.to_s, '--json'], cwd: root)
        expect(JSON.parse(out)['tasks'].map { |t| t['id'] }).to contain_exactly('TASK-0001', 'TASK-0002')
      end
    end

    it 'returns task_not_found for an unknown TASK-ID' do
      with_tmp_project do |root|
        init_composite(root)
        run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)
        exit_code, _out, err = run(['task', 'tree', 'TASK-9999', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(err).dig('error', 'code')).to eq('task_not_found')
      end
    end
  end

  describe 'doctor referential-integrity checks (problem 9)' do
    it 'reports orphan children after a raw parent-dir removal' do
      with_tmp_project do |root|
        parent_and_children(root, 1)
        # Simulate a legacy non-recursive delete: nuke only the parent dir.
        FileUtils.rm_rf((root + 'tasks/TASK-0001').to_s)

        _e, out, = run(['doctor', '--root', root.to_s], cwd: root)
        body = JSON.parse(out)
        orphan_ids = body['orphans'].map { |o| o['task_id'] }
        expect(orphan_ids).to include('TASK-0002')
        expect(body['orphans'].find { |o| o['task_id'] == 'TASK-0002' }['parent_id']).to eq('TASK-0001')
      end
    end

    it 'reports dangling blocked_by references to missing tasks' do
      with_tmp_project do |root|
        parent_and_children(root, 2)
        run(['task', 'dep', 'add', 'TASK-0003', '--on', 'TASK-0002', '--root', root.to_s], cwd: root)
        FileUtils.rm_rf((root + 'tasks/TASK-0002').to_s)

        _e, out, = run(['doctor', '--root', root.to_s], cwd: root)
        body = JSON.parse(out)
        dangling = body['dangling_deps'].find { |d| d['task_id'] == 'TASK-0003' }
        expect(dangling['missing']).to include('TASK-0002')
      end
    end

    it 'reports no integrity drift for a healthy tree' do
      with_tmp_project do |root|
        parent_and_children(root, 2)
        _e, out, = run(['doctor', '--root', root.to_s], cwd: root)
        body = JSON.parse(out)
        expect(body['orphans']).to be_empty
        expect(body['dangling_deps']).to be_empty
      end
    end
  end
end
