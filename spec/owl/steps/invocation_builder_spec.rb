# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'
require 'owl/steps/api'

RSpec.describe Owl::Steps::Api, '.invocation' do
  def run_cli(argv, cwd:)
    Owl::Cli::Api.run(
      argv: argv, stdout: StringIO.new, stderr: StringIO.new, env: {}, cwd: cwd.to_s
    )
  end

  def seed_feature_project(root, kind: 'task')
    run_cli(['init', '--root', root.to_s], cwd: root)
    write_feature_workflow(root, kind: kind)
    write_artifact_types(root)
    create_initial_task(root)
  end

  def write_feature_workflow(root, kind:)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
      id: feature
      kind: #{kind}
      artifacts:
        brief:
          type: brief
          storage:
            role: tasks
            path: "{{task.id}}/brief.md"
        specs:
          type: spec
          multiple: true
          storage:
            role: tasks
            path: "{{task.id}}/specs/**/*.md"
      steps:
        - id: brief
          title: Create brief
          skill: owl.steps.brief
          creates: [brief]
        - id: specify
          title: Create specs
          skill: owl.steps.specify
          requires: [brief]
          creates: [specs]
    YAML
  end

  def write_artifact_types(root)
    write("#{root}/.owl/artifacts.yaml", <<~YAML)
      schema_version: 1
      artifacts:
        brief:
          source: "artifacts/brief/artifact.yaml"
        spec:
          source: "artifacts/spec/artifact.yaml"
    YAML
    write("#{root}/.owl/artifacts/brief/artifact.yaml", <<~YAML)
      id: brief
      kind: markdown
      default_template: templates/default.md
    YAML
    write("#{root}/.owl/artifacts/brief/templates/default.md", "# Brief\n")
    write("#{root}/.owl/artifacts/spec/artifact.yaml", "id: spec\nkind: markdown\n")
  end

  def create_initial_task(root)
    stdout = StringIO.new
    Owl::Cli::Api.run(
      argv: ['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s, '--json'],
      stdout: stdout, stderr: StringIO.new, env: {}, cwd: root.to_s
    )
    JSON.parse(stdout.string).dig('task', 'id')
  end

  def complete_step(root, task_id, step_id)
    run_cli(['step', 'start', task_id, step_id, '--root', root.to_s], cwd: root)
    run_cli(['step', 'complete', task_id, step_id, '--root', root.to_s], cwd: root)
  end

  it 'returns a ready-state invocation for the first step with no inputs and one output' do
    with_tmp_project do |root|
      task_id = seed_feature_project(root)

      result = described_class.invocation(root: root, task_id: task_id, step_id: 'brief')
      expect(result).to be_ok
      value = result.value
      expect(value[:schema_version]).to eq(1)
      expect(value[:task][:id]).to eq(task_id)
      expect(value[:task][:kind]).to eq('task')
      expect(value[:task][:workflow_key]).to eq('feature')
      expect(value[:step][:id]).to eq('brief')
      expect(value[:step][:skill]).to eq('owl.steps.brief')
      expect(value[:step][:status]).to eq('ready')
      expect(value[:inputs][:artifacts]).to be_empty
      expect(value[:outputs][:artifacts]).to include('brief')
    end
  end

  it 'resolves inputs from predecessor steps once they complete' do
    with_tmp_project do |root|
      task_id = seed_feature_project(root)
      complete_step(root, task_id, 'brief')

      result = described_class.invocation(root: root, task_id: task_id, step_id: 'specify')
      expect(result).to be_ok
      value = result.value
      expect(value[:inputs][:artifacts]).to include('brief')
      expect(value[:outputs][:artifacts]).to include('specs')
      expect(value[:outputs][:artifacts]['specs'][:multiple]).to be(true)
    end
  end

  it 'sets task.kind to composite_task when the workflow kind says so' do
    with_tmp_project do |root|
      task_id = seed_feature_project(root, kind: 'composite_task')
      result = described_class.invocation(root: root, task_id: task_id, step_id: 'brief')
      expect(result).to be_ok
      expect(result.value[:task][:kind]).to eq('composite_task')
    end
  end

  it 'returns step_not_ready when the step is blocked by an unmet dependency' do
    with_tmp_project do |root|
      task_id = seed_feature_project(root)
      result = described_class.invocation(root: root, task_id: task_id, step_id: 'specify')
      expect(result).to be_err
      expect(result.code).to eq(:step_not_ready)
      expect(result.details[:ready_steps]).to eq(['brief'])
    end
  end

  it 'falls back to template_present: false when the artifact type has no default_template' do
    with_tmp_project do |root|
      task_id = seed_feature_project(root)
      result = described_class.invocation(root: root, task_id: task_id, step_id: 'brief')
      out = result.value[:outputs][:artifacts]['brief']
      expect(out[:template_present]).to be(true)

      File.delete("#{root}/.owl/artifacts/brief/templates/default.md")
      again = described_class.invocation(root: root, task_id: task_id, step_id: 'brief')
      out_again = again.value[:outputs][:artifacts]['brief']
      expect(out_again[:template_present]).to be(false)
    end
  end

  it 'emits children ids for a composite parent collected from the index' do
    with_tmp_project do |root|
      parent_id = seed_feature_project(root, kind: 'composite_task')
      stdout = StringIO.new
      Owl::Cli::Api.run(
        argv: ['task', 'create', '--workflow', 'feature', '--title', 'child',
               '--parent', parent_id, '--root', root.to_s, '--json'],
        stdout: stdout, stderr: StringIO.new, env: {}, cwd: root.to_s
      )
      child_id = JSON.parse(stdout.string).dig('task', 'id')

      result = described_class.invocation(root: root, task_id: parent_id, step_id: 'brief')
      expect(result.value[:task][:children]).to eq([child_id])
    end
  end
end
