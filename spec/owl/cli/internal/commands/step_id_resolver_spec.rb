# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/cli/internal/commands/step_id_resolver'

RSpec.describe Owl::Cli::Internal::Commands::StepIdResolver do
  def cli(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def setup_project(root)
    cli(['init', '--root', root.to_s], cwd: root)
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
        - id: b
          requires: ["a"]
      artifacts: []
    YAML
    cli(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s], cwd: root)
    'TASK-0001'
  end

  def write_current_yaml(root, task_id)
    write("#{root}/.owl/local/current.yaml", YAML.dump('task_id' => task_id, 'set_at' => Time.now.utc.iso8601))
  end

  def write_lock(root, task_id:, step_id:, session_type: 'execution')
    write("#{root}/.owl/local/active_step.yaml", YAML.dump(
                                                   'schema_version' => 1,
                                                   'task_id' => task_id,
                                                   'step_id' => step_id,
                                                   'session_type' => session_type,
                                                   'declared_at' => Time.now.utc.iso8601
                                                 ))
  end

  def set_step_status(root, task_id, statuses)
    path = Pathname.new(root) + "tasks/#{task_id}/task.yaml"
    payload = YAML.safe_load(path.read, permitted_classes: [Time])
    payload['steps'] = payload['steps'].map { |s| s.merge('status' => statuses[s['id']] || s['status']) }
    path.write(YAML.dump(payload))
  end

  describe '.resolve_task_id' do
    it 'returns explicit when explicit is a non-empty string' do
      with_tmp_project do |root|
        setup_project(root)
        result = described_class.resolve_task_id(root: root, explicit: 'TASK-EXPLICIT')
        expect(result.ok?).to be(true)
        expect(result.value).to eq(task_id: 'TASK-EXPLICIT', source: 'explicit')
      end
    end

    it 'returns lock task_id when explicit is missing and lock exists' do
      with_tmp_project do |root|
        setup_project(root)
        write_lock(root, task_id: 'TASK-LOCK', step_id: 'a')
        result = described_class.resolve_task_id(root: root, explicit: nil)
        expect(result.ok?).to be(true)
        expect(result.value).to eq(task_id: 'TASK-LOCK', source: 'active_step_lock')
      end
    end

    it 'returns current_pointer when neither explicit nor lock present' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        write_current_yaml(root, task_id)
        result = described_class.resolve_task_id(root: root, explicit: nil)
        expect(result.ok?).to be(true)
        expect(result.value).to eq(task_id: task_id, source: 'current_pointer')
      end
    end

    it 'returns no_current_task when nothing is available' do
      with_tmp_project do |root|
        setup_project(root)
        result = described_class.resolve_task_id(root: root, explicit: nil)
        expect(result.err?).to be(true)
        expect(result.code).to eq(:no_current_task)
      end
    end

    it 'propagates active_step_lock_invalid without falling back to current_pointer' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        write("#{root}/.owl/local/active_step.yaml", 'not: [a yaml: mapping}')
        write_current_yaml(root, task_id)
        result = described_class.resolve_task_id(root: root, explicit: nil)
        expect(result.err?).to be(true)
        expect(result.code).to eq(:active_step_lock_invalid)
      end
    end
  end

  describe '.resolve_step_id' do
    it 'returns explicit when explicit is a non-empty string' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        result = described_class.resolve_step_id(
          root: root, task_id: task_id, explicit: 'plan', allow_running_inference: true
        )
        expect(result.value).to eq(step_id: 'plan', source: 'explicit')
      end
    end

    it 'returns lock step_id when explicit missing and lock matches task' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        write_lock(root, task_id: task_id, step_id: 'b')
        result = described_class.resolve_step_id(
          root: root, task_id: task_id, explicit: nil, allow_running_inference: true
        )
        expect(result.value).to eq(step_id: 'b', source: 'active_step_lock')
      end
    end

    it 'ignores lock whose task_id differs from resolved task_id' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        set_step_status(root, task_id, 'a' => 'running')
        write_lock(root, task_id: 'TASK-OTHER', step_id: 'a')
        result = described_class.resolve_step_id(
          root: root, task_id: task_id, explicit: nil, allow_running_inference: true
        )
        expect(result.value).to eq(step_id: 'a', source: 'running_step_inference')
      end
    end

    it 'returns invalid_arguments when inference disabled and no source available' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        result = described_class.resolve_step_id(
          root: root, task_id: task_id, explicit: nil, allow_running_inference: false
        )
        expect(result.err?).to be(true)
        expect(result.code).to eq(:invalid_arguments)
      end
    end

    it 'infers the single running step' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        set_step_status(root, task_id, 'b' => 'running')
        result = described_class.resolve_step_id(
          root: root, task_id: task_id, explicit: nil, allow_running_inference: true
        )
        expect(result.value).to eq(step_id: 'b', source: 'running_step_inference')
      end
    end

    it 'errors ambiguous_step with recoverable error_class when multiple steps run' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        set_step_status(root, task_id, 'a' => 'running', 'b' => 'running')
        result = described_class.resolve_step_id(
          root: root, task_id: task_id, explicit: nil, allow_running_inference: true
        )
        expect(result.err?).to be(true)
        expect(result.code).to eq(:ambiguous_step)
        expect(result.error_class).to eq(:recoverable)
        expect(result.details[:running_step_ids]).to contain_exactly('a', 'b')
      end
    end

    it 'errors ambiguous_step when no step is running' do
      with_tmp_project do |root|
        task_id = setup_project(root)
        result = described_class.resolve_step_id(
          root: root, task_id: task_id, explicit: nil, allow_running_inference: true
        )
        expect(result.err?).to be(true)
        expect(result.code).to eq(:ambiguous_step)
        expect(result.details[:running_step_ids]).to eq([])
      end
    end
  end
end
