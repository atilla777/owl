# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'CLI JSON output path keys via Api.local_paths reflection' do
  def run(argv, root)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def init_project(root)
    run(['init', '--root', root.to_s], root)
  end

  def seed_feature_workflow(root)
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
    write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
      id: feature
      kind: feature
      steps:
        - id: a
        - id: b
          requires: ["a"]
      artifacts: []
    YAML
    write("#{root}/.owl/workflows/composite_feature/workflow.yaml", <<~YAML)
      id: composite_feature
      kind: composite_task
      steps:
        - id: brief
          kind: noop
      artifacts:
        brief:
          type: brief
    YAML
  end

  describe 'task commands' do
    it 'task create prints task_path + index_path matching disk layout' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        _exit, stdout, = run(['task', 'create', '--workflow', 'feature', '--title', 'x',
                              '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body['task_path']).to eq("#{root}/tasks/TASK-0001/task.yaml")
        expect(body['index_path']).to eq("#{root}/tasks/index.yaml")
      end
    end

    it 'task inspect prints task_path matching disk layout' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 'x', '--root', root.to_s, '--json'], root)
        _exit, stdout, = run(['task', 'inspect', 'TASK-0001', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body['task_path']).to eq("#{root}/tasks/TASK-0001/task.yaml")
      end
    end

    it 'task list prints index_path matching disk layout' do
      with_tmp_project do |root|
        init_project(root)
        _exit, stdout, = run(['task', 'list', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body['index_path']).to eq("#{root}/tasks/index.yaml")
      end
    end

    it 'task current prints pointer_path + task_path matching disk layout' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 'x', '--root', root.to_s, '--json'], root)
        run(['task', 'use', 'TASK-0001', '--root', root.to_s, '--json'], root)
        _exit, stdout, = run(['task', 'current', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body['pointer_path']).to eq("#{root}/.owl/local/current.yaml")
        expect(body['task_path']).to eq("#{root}/tasks/TASK-0001/task.yaml")
      end
    end

    it 'task use prints pointer_path matching disk layout' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 'x', '--root', root.to_s, '--json'], root)
        _exit, stdout, = run(['task', 'use', 'TASK-0001', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body['pointer_path']).to eq("#{root}/.owl/local/current.yaml")
      end
    end

    it 'task index rebuild prints index_path matching disk layout' do
      with_tmp_project do |root|
        init_project(root)
        _exit, stdout, = run(['task', 'index', 'rebuild', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body['index_path']).to eq("#{root}/tasks/index.yaml")
      end
    end

    it 'task child create prints task_path matching disk layout' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        run(['task', 'create', '--workflow', 'composite_feature', '--title', 'p',
             '--root', root.to_s, '--json'], root)
        _exit, stdout, = run(['task', 'child', 'create', 'TASK-0001',
                              '--workflow', 'feature', '--title', 'c',
                              '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body['task_path']).to eq("#{root}/tasks/TASK-0002/task.yaml")
      end
    end
  end

  describe 'workflow commands' do
    it 'workflow show (legacy) prints source_path matching disk layout' do
      with_tmp_project do |root|
        init_project(root)
        _exit, stdout, = run(['workflow', 'show', 'feature', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body['source_path']).to eq("#{root}/.owl/workflows/feature/workflow.yaml")
      end
    end

    it 'workflow validate prints source_path matching disk layout' do
      with_tmp_project do |root|
        init_project(root)
        _exit, stdout, = run(['workflow', 'validate', 'feature', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body['source_path']).to eq("#{root}/.owl/workflows/feature/workflow.yaml")
      end
    end
  end

  describe 'artifact-type commands' do
    it 'artifact-type show prints source_path + template_path matching disk layout' do
      with_tmp_project do |root|
        init_project(root)
        _exit, stdout, = run(['artifact-type', 'show', 'brief', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body['source_path']).to eq("#{root}/.owl/artifacts/brief/artifact.yaml")
        expect(body['template_path']).to eq("#{root}/.owl/artifacts/brief/templates/default.md")
      end
    end

    it 'artifact-type validate prints source_path matching disk layout' do
      with_tmp_project do |root|
        init_project(root)
        _exit, stdout, = run(['artifact-type', 'validate', 'brief', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body['source_path']).to eq("#{root}/.owl/artifacts/brief/artifact.yaml")
      end
    end
  end

  describe 'no_local_view fallback (future non-FS backend)' do
    it 'task create omits task_path/index_path when local_paths returns Err' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        allow(Owl::Tasks::Api).to receive(:local_paths).and_return(
          Owl::Result.err(code: :no_local_view, message: 'x', details: { backend: 'Stub' })
        )
        _exit, stdout, = run(['task', 'create', '--workflow', 'feature', '--title', 'x',
                              '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body).not_to include('task_path', 'index_path')
      end
    end

    it 'task list omits index_path when local_paths returns Err' do
      with_tmp_project do |root|
        init_project(root)
        allow(Owl::Tasks::Api).to receive(:local_paths).and_return(
          Owl::Result.err(code: :no_local_view, message: 'x', details: { backend: 'Stub' })
        )
        _exit, stdout, = run(['task', 'list', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body).not_to include('index_path')
      end
    end

    it 'task inspect omits task_path when local_paths returns Err' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 'x', '--root', root.to_s, '--json'], root)
        allow(Owl::Tasks::Api).to receive(:local_paths).and_return(
          Owl::Result.err(code: :no_local_view, message: 'x', details: { backend: 'Stub' })
        )
        _exit, stdout, = run(['task', 'inspect', 'TASK-0001', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body).not_to include('task_path')
      end
    end

    it 'task current omits pointer_path/task_path when local_paths returns Err' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 'x', '--root', root.to_s, '--json'], root)
        run(['task', 'use', 'TASK-0001', '--root', root.to_s, '--json'], root)
        allow(Owl::Tasks::Api).to receive(:local_paths).and_return(
          Owl::Result.err(code: :no_local_view, message: 'x', details: { backend: 'Stub' })
        )
        _exit, stdout, = run(['task', 'current', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body).not_to include('pointer_path', 'task_path')
      end
    end

    it 'task use omits pointer_path when local_paths returns Err' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        run(['task', 'create', '--workflow', 'feature', '--title', 'x', '--root', root.to_s, '--json'], root)
        allow(Owl::Tasks::Api).to receive(:local_paths).and_return(
          Owl::Result.err(code: :no_local_view, message: 'x', details: { backend: 'Stub' })
        )
        _exit, stdout, = run(['task', 'use', 'TASK-0001', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body).not_to include('pointer_path')
      end
    end

    it 'task index rebuild omits index_path when local_paths returns Err' do
      with_tmp_project do |root|
        init_project(root)
        allow(Owl::Tasks::Api).to receive(:local_paths).and_return(
          Owl::Result.err(code: :no_local_view, message: 'x', details: { backend: 'Stub' })
        )
        _exit, stdout, = run(['task', 'index', 'rebuild', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body).not_to include('index_path')
      end
    end

    it 'task child create omits task_path when local_paths returns Err' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        run(['task', 'create', '--workflow', 'composite_feature', '--title', 'p',
             '--root', root.to_s, '--json'], root)
        allow(Owl::Tasks::Api).to receive(:local_paths).and_return(
          Owl::Result.err(code: :no_local_view, message: 'x', details: { backend: 'Stub' })
        )
        _exit, stdout, = run(['task', 'child', 'create', 'TASK-0001',
                              '--workflow', 'feature', '--title', 'c',
                              '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body).not_to include('task_path')
      end
    end

    it 'workflow show omits source_path when local_paths returns Err' do
      with_tmp_project do |root|
        init_project(root)
        allow(Owl::Workflows::Api).to receive(:local_paths).and_return(
          Owl::Result.err(code: :no_local_view, message: 'x', details: { backend: 'Stub' })
        )
        _exit, stdout, = run(['workflow', 'show', 'feature', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body).not_to include('source_path')
      end
    end

    it 'workflow validate omits source_path when local_paths returns Err' do
      with_tmp_project do |root|
        init_project(root)
        allow(Owl::Workflows::Api).to receive(:local_paths).and_return(
          Owl::Result.err(code: :no_local_view, message: 'x', details: { backend: 'Stub' })
        )
        _exit, stdout, = run(['workflow', 'validate', 'feature', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body).not_to include('source_path')
      end
    end

    it 'artifact-type show omits source_path/template_path when local_paths returns Err' do
      with_tmp_project do |root|
        init_project(root)
        allow(Owl::Artifacts::Api).to receive(:local_paths).and_return(
          Owl::Result.err(code: :no_local_view, message: 'x', details: { backend: 'Stub' })
        )
        _exit, stdout, = run(['artifact-type', 'show', 'brief', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body).not_to include('source_path', 'template_path')
      end
    end

    it 'artifact-type validate omits source_path when local_paths returns Err' do
      with_tmp_project do |root|
        init_project(root)
        allow(Owl::Artifacts::Api).to receive(:local_paths).and_return(
          Owl::Result.err(code: :no_local_view, message: 'x', details: { backend: 'Stub' })
        )
        _exit, stdout, = run(['artifact-type', 'validate', 'brief', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body).not_to include('source_path')
      end
    end

    it 'workflow new omits path when local_paths returns Err' do
      with_tmp_project do |root|
        init_project(root)
        allow(Owl::Workflows::Api).to receive(:local_paths).and_return(
          Owl::Result.err(code: :no_local_view, message: 'x', details: { backend: 'Stub' })
        )
        _exit, stdout, = run(['workflow', 'new', '--id', 'demo', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body).not_to include('path')
      end
    end

    it 'artifact-type new omits path/template_path when local_paths returns Err' do
      with_tmp_project do |root|
        init_project(root)
        allow(Owl::Artifacts::Api).to receive(:local_paths).and_return(
          Owl::Result.err(code: :no_local_view, message: 'x', details: { backend: 'Stub' })
        )
        _exit, stdout, = run(['artifact-type', 'new', '--id', 'demo_at', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body).not_to include('path', 'template_path')
      end
    end

    it 'step commands omit task_path when local_paths returns Err' do
      with_tmp_project do |root|
        init_project(root)
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
          artifacts: []
        YAML
        run(['task', 'create', '--workflow', 'feature', '--title', 't',
             '--root', root.to_s, '--json'], root)
        allow(Owl::Steps::Api).to receive(:local_paths).and_return(
          Owl::Result.err(code: :no_local_view, message: 'x', details: { backend: 'Stub' })
        )
        _exit, stdout, = run(['step', 'start', 'TASK-0001', 'a', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body).not_to include('task_path')
      end
    end
  end

  describe 'step commands' do
    def setup_step_project(root)
      init_project(root)
      seed_feature_workflow(root)
      run(['task', 'create', '--workflow', 'feature', '--title', 't',
           '--root', root.to_s, '--json'], root)
      'TASK-0001'
    end

    it 'step start prints task_path matching disk layout' do
      with_tmp_project do |root|
        task_id = setup_step_project(root)
        _exit, stdout, = run(['step', 'start', task_id, 'a', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body['task_path']).to eq("#{root}/tasks/#{task_id}/task.yaml")
      end
    end

    it 'step complete prints task_path matching disk layout' do
      with_tmp_project do |root|
        task_id = setup_step_project(root)
        run(['step', 'start', task_id, 'a', '--root', root.to_s, '--json'], root)
        _exit, stdout, = run(['step', 'complete', task_id, 'a', '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body['task_path']).to eq("#{root}/tasks/#{task_id}/task.yaml")
      end
    end

    it 'step skip prints task_path matching disk layout' do
      with_tmp_project do |root|
        task_id = setup_step_project(root)
        _exit, stdout, = run(['step', 'skip', task_id, 'a', '--reason', 'x',
                              '--root', root.to_s, '--json'], root)
        body = JSON.parse(stdout)
        expect(body['task_path']).to eq("#{root}/tasks/#{task_id}/task.yaml")
      end
    end
  end
end
