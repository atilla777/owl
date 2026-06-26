# frozen_string_literal: true

require 'stringio'

require 'owl/cli/api'
require 'owl/tasks/api'
require 'owl/orchestration/internal/task_resolver'

RSpec.describe Owl::Orchestration::Internal::TaskResolver do
  def cli(argv, root)
    Owl::Cli::Api.run(argv: argv, stdout: StringIO.new, stderr: StringIO.new, env: {}, cwd: root.to_s)
  end

  def setup_project(root)
    cli(['init', '--root', root.to_s], root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
      id: feature
      kind: task
      artifacts: {}
      steps:
        - id: a
    YAML
  end

  def create_task(root, title: 't')
    cli(['task', 'create', '--workflow', 'feature', '--title', title, '--root', root.to_s, '--json'], root)
  end

  describe '.resolve' do
    it 'returns the explicit task_id without touching state' do
      with_tmp_project do |root|
        setup_project(root)
        result = described_class.resolve(root: root, task_id: 'TASK-0042')
        expect(result).to eq(
          task_id: 'TASK-0042', source: 'explicit', reason: 'explicit TASK-ID requested'
        )
      end
    end

    it 'resolves from the current pointer when one is set' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root)
        cli(['task', 'use', 'TASK-0001', '--root', root.to_s], root)
        result = described_class.resolve(root: root)
        expect(result[:task_id]).to eq('TASK-0001')
        expect(result[:source]).to eq('current_pointer')
      end
    end

    it 'auto-selects the top dep-aware ready task when there is no current pointer' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root, title: 'normal')
        result = described_class.resolve(root: root)
        expect(result[:task_id]).to eq('TASK-0001')
        expect(result[:source]).to eq('auto_select')
      end
    end

    it 'does not auto-select a dep-blocked top task' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root, title: 'dep')
        create_task(root, title: 'blocked')
        Owl::Tasks::Api.add_dependency(root: root, task_id: 'TASK-0002', depends_on: 'TASK-0001')
        Owl::Tasks::Api.set_priority(root: root, task_id: 'TASK-0002', priority: 9)
        result = described_class.resolve(root: root)
        # TASK-0002 outranks by priority but is dep-blocked, so the dep-free
        # TASK-0001 is selected instead.
        expect(result[:task_id]).to eq('TASK-0001')
        expect(result[:source]).to eq('auto_select')
      end
    end

    it 'does not auto-select an on_hold top task' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root, title: 'parked')
        Owl::Tasks::Api.set_status(root: root, task_id: 'TASK-0001', status: 'on_hold')
        result = described_class.resolve(root: root)
        expect(result[:task_id]).to be_nil
        expect(result[:source]).to eq('none')
      end
    end

    it 'falls through a terminal current pointer to auto-select another runnable task' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root, title: 'dead')  # TASK-0001
        create_task(root, title: 'alive') # TASK-0002
        cli(['task', 'use', 'TASK-0001', '--root', root.to_s], root)
        Owl::Tasks::Api.abandon(root: root, task_id: 'TASK-0001')
        # `abandon` already clears the pointer, so re-point it at the terminal
        # task to exercise the resolver's own terminal fallback in isolation.
        cli(['task', 'use', 'TASK-0001', '--root', root.to_s], root)

        result = described_class.resolve(root: root)
        expect(result[:task_id]).to eq('TASK-0002')
        expect(result[:source]).to eq('auto_select')
      end
    end

    it 'returns none when the current pointer is terminal and nothing else is runnable' do
      with_tmp_project do |root|
        setup_project(root)
        create_task(root, title: 'dead') # TASK-0001
        cli(['task', 'use', 'TASK-0001', '--root', root.to_s], root)
        Owl::Tasks::Api.abandon(root: root, task_id: 'TASK-0001')
        cli(['task', 'use', 'TASK-0001', '--root', root.to_s], root)

        result = described_class.resolve(root: root)
        expect(result[:task_id]).to be_nil
        expect(result[:source]).to eq('none')
      end
    end
  end
end
