# frozen_string_literal: true

require 'owl/tasks/api'
require 'owl/tasks/backends/filesystem'
require 'owl/cli/internal/commands/init'

RSpec.describe Owl::Tasks::Backends::Filesystem do
  def init_project(root)
    Owl::Cli::Internal::Commands::Init.run(
      argv: ['--root', root.to_s],
      stdout: StringIO.new,
      stderr: StringIO.new,
      cwd: root.to_s,
      env: {}
    )
  end

  def seed_feature_workflow(root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
          version: "1.0"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
      id: feature
      kind: feature
      title: Feature workflow
      steps:
        - id: noop
          kind: noop
      artifacts: []
    YAML
  end

  it 'includes the Owl::Tasks::Backend contract' do
    expect(described_class.included_modules).to include(Owl::Tasks::Backend)
  end

  describe 'instance contract' do
    it 'responds to every method declared by Owl::Tasks::Backend' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)
        Owl::Tasks::Backend.instance_methods(false).each do |method_name|
          expect(backend).to respond_to(method_name), "missing backend method: #{method_name}"
        end
      end
    end
  end

  describe 'happy-path delegation' do
    it 'create + list + inspect_task return the same results as the legacy api' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        backend = described_class.new(root: root)

        create_result = backend.create(workflow: 'feature', title: 'first')
        expect(create_result).to be_ok
        expect(create_result.value[:task_id]).to eq('TASK-0001')

        list_result = backend.list
        expect(list_result).to be_ok
        expect(list_result.value[:tasks].map { |t| t['id'] }).to eq(['TASK-0001'])

        inspect_result = backend.inspect_task(task_id: 'TASK-0001')
        expect(inspect_result).to be_ok
        expect(inspect_result.value[:payload]['title']).to eq('first')
      end
    end

    it 'use + current round-trip' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_workflow(root)
        backend = described_class.new(root: root)
        backend.create(workflow: 'feature', title: 'first')

        backend.use(task_id: 'TASK-0001')
        current_result = backend.current
        expect(current_result).to be_ok
        expect(current_result.value[:task_id]).to eq('TASK-0001')
      end
    end
  end

  describe '#archive_task' do
    it 'raises NotImplementedError until subtask #112 lands' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)
        expect { backend.archive_task(task_id: 'TASK-0001') }
          .to raise_error(NotImplementedError, /subtask #112/)
      end
    end
  end
end
