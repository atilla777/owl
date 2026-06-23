# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/archive/api'
require 'owl/cli/api'
require 'owl/tasks/api'
require 'owl/tasks/internal/children_lister'

# Regression coverage for TASK-0019: the composite `children_complete` gate must
# open once every child is archived (a child that ran `owl archive CHILD` leaves
# tasks/index.yaml, but is still its parent's child via the archived task.yaml's
# parent_id). A parent that never had children must still aggregate `open`.
RSpec.describe 'Owl aggregate-status with archived children' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [code, stdout.string, stderr.string]
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
        - id: archive
          gate: children_complete
      artifacts: []
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml",
          "id: feature\nkind: task\nsteps:\n  - id: do\nartifacts: []\n")
  end

  def create_parent(root)
    run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)
  end

  def create_child(root, parent_id, title)
    _, stdout, = run(
      ['task', 'create', '--workflow', 'feature', '--title', title, '--parent', parent_id,
       '--root', root.to_s, '--json'], cwd: root
    )
    JSON.parse(stdout).dig('task', 'id')
  end

  def archive_child(root, child_id)
    run(['step', 'start', child_id, 'do', '--root', root.to_s], cwd: root)
    run(['step', 'complete', child_id, 'do', '--root', root.to_s], cwd: root)
    run(['archive', child_id, '--root', root.to_s, '--json'], cwd: root)
  end

  it 'opens the gate when the only child self-archived (wedge fixed)' do
    with_tmp_project do |root|
      init_with_workflows(root)
      create_parent(root)
      child_id = create_child(root, 'TASK-0001', 'C')
      archive_child(root, child_id)

      result = Owl::Tasks::Api.aggregate_status(root: root, task_id: 'TASK-0001')

      aggregate_failures do
        expect(result.ok?).to be(true)
        expect(result.value[:aggregate]).to eq('done')
        archived = result.value[:by_child].find { |c| c[:id] == child_id }
        expect(archived).to include(state: 'archived', status: 'archived')

        _, ready_out, = run(['task', 'ready-steps', 'TASK-0001', '--root', root.to_s, '--json'], cwd: root)
        ready_ids = JSON.parse(ready_out)['ready'].map { |s| s['id'] }
        expect(ready_ids).to include('archive')
      end
    end
  end

  it 'does not report done when one child is archived and another is still active' do
    with_tmp_project do |root|
      init_with_workflows(root)
      create_parent(root)
      archived_child = create_child(root, 'TASK-0001', 'archived-one')
      active_child = create_child(root, 'TASK-0001', 'active-one')
      archive_child(root, archived_child)

      result = Owl::Tasks::Api.aggregate_status(root: root, task_id: 'TASK-0001')

      aggregate_failures do
        expect(result.ok?).to be(true)
        expect(result.value[:aggregate]).not_to eq('done')
        states = result.value[:by_child].to_h { |c| [c[:id], c[:state]] }
        expect(states[archived_child]).to eq('archived')
        expect(states[active_child]).to eq('in_progress')
      end
    end
  end

  it 'keeps aggregate open for a composite parent that never had children' do
    with_tmp_project do |root|
      init_with_workflows(root)
      create_parent(root)

      result = Owl::Tasks::Api.aggregate_status(root: root, task_id: 'TASK-0001')

      aggregate_failures do
        expect(result.ok?).to be(true)
        expect(result.value[:aggregate]).to eq('open')
        expect(result.value[:by_child]).to eq([])
      end
    end
  end

  it 'exposes parent_id on archived entries via Owl::Archive::Api.list' do
    with_tmp_project do |root|
      init_with_workflows(root)
      create_parent(root)
      child_id = create_child(root, 'TASK-0001', 'C')
      archive_child(root, child_id)

      result = Owl::Archive::Api.list(root: root)

      aggregate_failures do
        expect(result.ok?).to be(true)
        entry = result.value[:archived].find { |e| e[:task_id] == child_id }
        expect(entry).not_to be_nil
        expect(entry).to have_key(:parent_id)
        expect(entry[:parent_id]).to eq('TASK-0001')
      end
    end
  end

  it 'merges index + archive children with dedup in ChildrenLister' do
    with_tmp_project do |root|
      init_with_workflows(root)
      create_parent(root)
      archived_child = create_child(root, 'TASK-0001', 'archived-one')
      active_child = create_child(root, 'TASK-0001', 'active-one')
      archive_child(root, archived_child)

      result = Owl::Tasks::Internal::ChildrenLister.call(root: root, parent_id: 'TASK-0001')

      aggregate_failures do
        expect(result.ok?).to be(true)
        by_id = result.value[:children].to_h { |c| [c[:id], c] }
        # No duplicate ids (dedup holds even though only one is archived here).
        ids = result.value[:children].map { |c| c[:id] }
        expect(ids).to eq(ids.uniq)
        expect(ids).to contain_exactly(archived_child, active_child)
        expect(by_id[archived_child][:status]).to eq('archived')
        expect(by_id[active_child][:status]).not_to eq('archived')
      end
    end
  end
end
