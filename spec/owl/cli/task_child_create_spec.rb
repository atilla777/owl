# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'owl task child create + owl task create --parent allowed_children enforcement' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def init_strict_composite(root)
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

  it 'task child create returns exit 1 + JSON envelope when child workflow not allowed (ac-5)' do
    with_tmp_project do |root|
      init_strict_composite(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)

      exit_code, _stdout, stderr = run(
        ['task', 'child', 'create', 'TASK-0001',
         '--workflow', 'bug_investigation', '--title', 'C', '--root', root.to_s],
        cwd: root
      )

      expect(exit_code).to eq(1)
      payload = JSON.parse(stderr)
      expect(payload['ok']).to be(false)
      expect(payload.dig('error', 'code')).to eq('child_workflow_not_allowed')
      expect(payload.dig('error', 'error_class')).to eq('validation')
      details = payload.dig('error', 'details')
      expect(details).to include(
        'parent_id' => 'TASK-0001',
        'parent_workflow_key' => 'composite_feature',
        'child_workflow_key' => 'bug_investigation',
        'allowed_children' => ['feature']
      )
      expect(payload.dig('error', 'message')).to include("'bug_investigation'")
      expect(payload.dig('error', 'message')).to include('Allowed:')
    end
  end

  it 'child create --brief prints a payload with brief: done, not stale pending (TASK-0023 FF4)' do
    with_tmp_project do |root|
      init_strict_composite(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)
      brief_file = root + 'child-brief.md'
      brief_file.write("# Child brief\n\nbody\n")

      exit_code, stdout, _stderr = run(
        ['task', 'child', 'create', 'TASK-0001',
         '--workflow', 'feature', '--title', 'C', '--brief', brief_file.to_s, '--root', root.to_s],
        cwd: root
      )

      expect(exit_code).to eq(0)
      payload = JSON.parse(stdout)
      expect(payload['ok']).to be(true)
      brief_step = payload.dig('task', 'steps').find { |s| s['id'] == 'brief' }
      expect(brief_step['status']).to eq('done')
    end
  end

  it 'task create --parent returns exit 1 + identical JSON envelope (ac-6)' do
    with_tmp_project do |root|
      init_strict_composite(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)

      exit_code, _stdout, stderr = run(
        ['task', 'create',
         '--workflow', 'bug_investigation', '--title', 'C',
         '--parent', 'TASK-0001', '--root', root.to_s],
        cwd: root
      )

      expect(exit_code).to eq(1)
      payload = JSON.parse(stderr)
      expect(payload['ok']).to be(false)
      expect(payload.dig('error', 'code')).to eq('child_workflow_not_allowed')
      expect(payload.dig('error', 'error_class')).to eq('validation')
      details = payload.dig('error', 'details')
      expect(details).to include(
        'parent_id' => 'TASK-0001',
        'parent_workflow_key' => 'composite_feature',
        'child_workflow_key' => 'bug_investigation',
        'allowed_children' => ['feature']
      )
    end
  end
end
