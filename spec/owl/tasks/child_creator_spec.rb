# frozen_string_literal: true

require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/tasks/api'

RSpec.describe 'Owl::Tasks::Api.child_create' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
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

  it 'creates a child task under a composite parent' do
    with_tmp_project do |root|
      init_with_workflows(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)

      result = Owl::Tasks::Api.child_create(root: root, parent_id: 'TASK-0001', workflow: 'feature', title: 'C')
      expect(result.ok?).to be(true)
      expect(result.value[:task_id]).to eq('TASK-0002')
      expect(result.value[:payload]['parent_id']).to eq('TASK-0001')
    end
  end

  it 'refuses when parent is not a composite_task' do
    with_tmp_project do |root|
      init_with_workflows(root)
      run(['task', 'create', '--workflow', 'feature', '--title', 'plain', '--root', root.to_s], cwd: root)

      result = Owl::Tasks::Api.child_create(root: root, parent_id: 'TASK-0001', workflow: 'feature', title: 'C')
      expect(result.err?).to be(true)
      expect(result.code).to eq(:parent_not_composite)
    end
  end

  it 'refuses when parent does not exist' do
    with_tmp_project do |root|
      init_with_workflows(root)
      result = Owl::Tasks::Api.child_create(root: root, parent_id: 'TASK-9999', workflow: 'feature', title: 'C')
      expect(result.err?).to be(true)
      expect(result.code).to eq(:task_not_found)
    end
  end

  it 'detects parent_chain_cycle when task.yaml files form a cycle' do
    with_tmp_project do |root|
      init_with_workflows(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'A', '--root', root.to_s], cwd: root)
      run(
        ['task', 'create', '--workflow', 'composite_feature', '--title', 'B', '--parent', 'TASK-0001', '--root',
         root.to_s], cwd: root
      )
      a_path = root + 'tasks/TASK-0001/task.yaml'
      a_payload = YAML.safe_load(a_path.read, aliases: false, permitted_classes: [Time])
      a_payload['parent_id'] = 'TASK-0002'
      a_path.write(YAML.dump(a_payload))

      result = Owl::Tasks::Api.child_create(root: root, parent_id: 'TASK-0002', workflow: 'feature', title: 'C')
      expect(result.err?).to be(true)
      expect(result.code).to eq(:parent_chain_cycle)
    end
  end

  it 'seeds the child brief.md and marks the brief step done when brief_body is given' do
    with_tmp_project do |root|
      init_with_workflows(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)

      body = "# Child brief\n\nAuthored by parent decompose.\n"
      result = Owl::Tasks::Api.child_create(
        root: root, parent_id: 'TASK-0001', workflow: 'feature', title: 'C', brief_body: body
      )
      expect(result.ok?).to be(true)

      child_id = result.value[:task_id]
      brief_path = root + "tasks/#{child_id}/brief.md"
      expect(brief_path.exist?).to be(true)
      expect(brief_path.read).to eq(body)

      payload = YAML.safe_load((root + "tasks/#{child_id}/task.yaml").read, aliases: false, permitted_classes: [Time])
      brief_step = payload['steps'].find { |s| s['id'] == 'brief' }
      expect(brief_step['status']).to eq('done')
    end
  end

  it 'leaves brief step pending when no brief_body provided' do
    with_tmp_project do |root|
      init_with_workflows(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)

      result = Owl::Tasks::Api.child_create(root: root, parent_id: 'TASK-0001', workflow: 'feature', title: 'C')
      expect(result.ok?).to be(true)

      child_id = result.value[:task_id]
      brief_path = root + "tasks/#{child_id}/brief.md"
      expect(brief_path.exist?).to be(false)

      payload = YAML.safe_load((root + "tasks/#{child_id}/task.yaml").read, aliases: false, permitted_classes: [Time])
      brief_step = payload['steps'].find { |s| s['id'] == 'brief' }
      expect(brief_step['status']).to eq('pending')
    end
  end

  # Rewrites the composite_feature workflow.yaml in a project that was already
  # initialised via init_with_workflows, injecting an `allowed_children:` line.
  def init_with_allowed_children(root, allowed:)
    write("#{root}/.owl/workflows/composite_feature/workflow.yaml", <<~YAML)
      id: composite_feature
      kind: composite_task
      allowed_children: #{allowed.inspect}
      artifacts:
        brief:
          type: brief
          storage:
            role: tasks
            path: "{{task.id}}/brief.md"
      steps:
        - id: only
    YAML
  end

  it 'allows any child when parent workflow has no allowed_children (ac-4)' do
    with_tmp_project do |root|
      init_with_workflows(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)

      result = Owl::Tasks::Api.child_create(root: root, parent_id: 'TASK-0001', workflow: 'feature', title: 'C')
      expect(result.ok?).to be(true)
      expect(result.value[:payload]['parent_id']).to eq('TASK-0001')
    end
  end

  it 'allows a whitelisted child when parent workflow declares allowed_children (ac-7 positive)' do
    with_tmp_project do |root|
      init_with_workflows(root)
      init_with_allowed_children(root, allowed: ['feature'])
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)

      result = Owl::Tasks::Api.child_create(root: root, parent_id: 'TASK-0001', workflow: 'feature', title: 'C')
      expect(result.ok?).to be(true)
    end
  end

  it 'rejects a non-whitelisted child with child_workflow_not_allowed (ac-5, ac-7 negative)' do
    with_tmp_project do |root|
      init_with_workflows(root)
      init_with_allowed_children(root, allowed: ['feature'])
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)

      result = Owl::Tasks::Api.child_create(
        root: root, parent_id: 'TASK-0001', workflow: 'composite_feature', title: 'C'
      )
      expect(result.err?).to be(true)
      expect(result.code).to eq(:child_workflow_not_allowed)
      expect(result.details).to include(
        parent_id: 'TASK-0001',
        parent_workflow_key: 'composite_feature',
        child_workflow_key: 'composite_feature',
        allowed_children: ['feature']
      )
      expect(result.message).to include("'composite_feature'")
      expect(result.message).to include('Allowed:')
    end
  end

  it 'rejects every child when allowed_children is [] (strict deny)' do
    with_tmp_project do |root|
      init_with_workflows(root)
      init_with_allowed_children(root, allowed: [])
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)

      result = Owl::Tasks::Api.child_create(root: root, parent_id: 'TASK-0001', workflow: 'feature', title: 'C')
      expect(result.err?).to be(true)
      expect(result.code).to eq(:child_workflow_not_allowed)
      expect(result.details[:allowed_children]).to eq([])
    end
  end
end
