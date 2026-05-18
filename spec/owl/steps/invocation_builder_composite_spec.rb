# frozen_string_literal: true

require 'stringio'

require 'owl/cli/api'
require 'owl/steps/api'

RSpec.describe 'Owl::Steps::Api.invocation composite-aware blocks' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
  end

  def init_with_composite_workflow(root)
    run(['init', '--root', root.to_s], cwd: root)
    write_registry(root)
    write_composite_workflow(root)
    write_slice_workflow(root)
  end

  def write_registry(root)
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
  end

  def write_composite_workflow(root)
    write("#{root}/.owl/workflows/composite_feature/workflow.yaml", <<~YAML)
      id: composite_feature
      kind: composite_task
      artifacts:
        verification:
          type: verification
          storage:
            role: tasks
            path: "{{task.id}}/verification.md"
      steps:
        - id: decompose
          skill: owl-step-run
        - id: coordinate
          skill: owl-step-run
          requires: [decompose]
        - id: aggregate_verify
          skill: owl-step-run
          requires: [coordinate]
          creates: [verification]
    YAML
  end

  def write_slice_workflow(root)
    write("#{root}/.owl/workflows/feature_slice/workflow.yaml", <<~YAML)
      id: feature_slice
      kind: task
      artifacts:
        verification:
          type: verification
          storage:
            role: tasks
            path: "{{task.id}}/verification.md"
      steps:
        - id: verify
          skill: owl-step-run
          creates: [verification]
    YAML
  end

  it 'decompose: returns children_target_paths in outputs' do
    with_tmp_project do |root|
      init_with_composite_workflow(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)

      result = Owl::Steps::Api.invocation(root: root, task_id: 'TASK-0001', step_id: 'decompose')
      expect(result.ok?).to be(true)
      expect(result.value[:outputs][:children_target_paths]).to eq([])
    end
  end

  it 'coordinate: returns children list in inputs' do
    with_tmp_project do |root|
      init_with_composite_workflow(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)
      run(
        ['task', 'create', '--workflow', 'feature_slice', '--title', 'C', '--parent', 'TASK-0001', '--root',
         root.to_s], cwd: root
      )
      # Mark decompose done so coordinate becomes ready.
      run(['step', 'start', 'TASK-0001', 'decompose', '--root', root.to_s], cwd: root)
      run(['step', 'complete', 'TASK-0001', 'decompose', '--root', root.to_s], cwd: root)

      result = Owl::Steps::Api.invocation(root: root, task_id: 'TASK-0001', step_id: 'coordinate')
      expect(result.ok?).to be(true)
      ids = result.value[:inputs][:children].map { |c| c[:id] }
      expect(ids).to eq(['TASK-0002'])
    end
  end

  it 'aggregate_verify: returns children_verification_paths for children with verification artifact present' do
    with_tmp_project do |root|
      init_with_composite_workflow(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)
      run(
        ['task', 'create', '--workflow', 'feature_slice', '--title', 'C', '--parent', 'TASK-0001', '--root',
         root.to_s], cwd: root
      )
      verification_path = root + 'tasks/TASK-0002/verification.md'
      verification_path.write(<<~MD)
        ---
        status: passed
        verification_passed: true
        summary: ok
        ---

        ## Summary

        ok

        ## Commands

        none

        ## Outcomes

        ok
      MD
      # Complete decompose + coordinate so aggregate_verify is ready.
      %w[decompose coordinate].each do |sid|
        run(['step', 'start', 'TASK-0001', sid, '--root', root.to_s], cwd: root)
        run(['step', 'complete', 'TASK-0001', sid, '--root', root.to_s], cwd: root)
      end

      result = Owl::Steps::Api.invocation(root: root, task_id: 'TASK-0001', step_id: 'aggregate_verify')
      expect(result.ok?).to be(true)
      paths = result.value[:inputs][:children_verification_paths]
      expect(paths.size).to eq(1)
      expect(paths.first[:child_id]).to eq('TASK-0002')
      expect(paths.first[:path]).to end_with('tasks/TASK-0002/verification.md')
    end
  end
end
