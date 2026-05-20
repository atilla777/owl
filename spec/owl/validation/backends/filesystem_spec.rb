# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/validation/backend'
require 'owl/validation/backends/filesystem'

RSpec.describe Owl::Validation::Backends::Filesystem do
  def init_project(root)
    Owl::Cli::Api.run(argv: ['init', '--root', root.to_s], stdout: StringIO.new, stderr: StringIO.new,
                      env: {}, cwd: root.to_s)
  end

  def base_workflow_yaml
    <<~YAML
      id: feature
      kind: task
      artifacts:
        brief:
          type: brief
          storage:
            role: tasks
            path: "{{task.id}}/brief.md"
        spec:
          type: spec
          storage:
            role: tasks
            path: "{{task.id}}/spec.md"
      steps:
        - id: brief
          creates: [brief]
        - id: specify
          requires: [brief]
          creates: [spec]
    YAML
  end

  def seed_full_project(root)
    init_project(root)
    seed_workflow_registry(root)
    seed_artifact_registry(root)
    seed_artifact_types(root)
    create_initial_task(root)
  end

  def seed_workflow_registry(root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", base_workflow_yaml)
  end

  def seed_artifact_registry(root)
    write("#{root}/.owl/artifacts.yaml", <<~YAML)
      schema_version: 1
      artifacts:
        brief:
          source: "artifacts/brief/artifact.yaml"
        spec:
          source: "artifacts/spec/artifact.yaml"
    YAML
  end

  def seed_artifact_types(root)
    write("#{root}/.owl/artifacts/brief/artifact.yaml", <<~YAML)
      id: brief
      kind: markdown
      validation:
        required_sections:
          - Summary
    YAML
    write("#{root}/.owl/artifacts/spec/artifact.yaml", <<~YAML)
      id: spec
      kind: markdown
      front_matter:
        type: object
        required:
          - status
          - summary
        properties:
          status:
            type: string
            enum:
              - draft
              - approved
          summary:
            type: string
    YAML
  end

  def create_initial_task(root)
    stdout = StringIO.new
    Owl::Cli::Api.run(argv: ['task', 'create', '--workflow', 'feature', '--title', 't',
                             '--root', root.to_s, '--json'],
                      stdout: stdout, stderr: StringIO.new, env: {}, cwd: root.to_s)
    JSON.parse(stdout.string).dig('task', 'id')
  end

  it 'includes the Owl::Validation::Backend contract' do
    expect(described_class.included_modules).to include(Owl::Validation::Backend)
  end

  describe 'instance contract' do
    it 'responds to every method declared by Owl::Validation::Backend' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)
        Owl::Validation::Backend.instance_methods(false).each do |method_name|
          expect(backend).to respond_to(method_name), "missing backend method: #{method_name}"
        end
      end
    end
  end

  describe '#artifact' do
    it 'returns valid: true when required sections are present' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        write("#{root}/tasks/#{task_id}/brief.md", "## Summary\n\nbody.\n")

        result = described_class.new(root: root).artifact(task_id: task_id, artifact_key: 'brief')
        expect(result).to be_ok
        expect(result.value[:valid]).to be(true)
      end
    end

    it 'returns missing_artifact violation when the file is absent' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        result = described_class.new(root: root).artifact(task_id: task_id, artifact_key: 'brief')
        expect(result).to be_ok
        expect(result.value[:valid]).to be(false)
        expect(result.value[:violations].first[:type]).to eq('missing_artifact')
      end
    end

    it 'returns Err with unknown_workflow_artifact for unknown keys' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        result = described_class.new(root: root).artifact(task_id: task_id, artifact_key: 'nope')
        expect(result).to be_err
        expect(result.code).to eq(:unknown_workflow_artifact)
      end
    end
  end

  describe '#task' do
    it 'aggregates per-artifact validation across the workflow' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        write("#{root}/tasks/#{task_id}/brief.md", "## Summary\n\nbody\n")
        write("#{root}/tasks/#{task_id}/spec.md", <<~MD)
          ---
          status: draft
          summary: ok
          ---

          # Spec
        MD

        result = described_class.new(root: root).task(task_id: task_id)
        expect(result).to be_ok
        expect(result.value[:all_valid]).to be(true)
        keys = result.value[:results].map { |r| r[:artifact_key] }
        expect(keys).to contain_exactly('brief', 'spec')
      end
    end

    it 'returns task_workflow_missing when task.yaml lacks workflow key' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        task_path = "#{root}/tasks/#{task_id}/task.yaml"
        payload = YAML.safe_load_file(task_path, permitted_classes: [Date, Time], aliases: false)
        payload.delete('workflow')
        write(task_path, YAML.dump(payload))

        result = described_class.new(root: root).task(task_id: task_id)
        expect(result).to be_err
        expect(result.code).to eq(:task_workflow_missing)
      end
    end

    it 'returns workflow_source_missing when the workflow source file is gone' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        File.delete("#{root}/.owl/workflows/feature/workflow.yaml")
        result = described_class.new(root: root).task(task_id: task_id)
        expect(result).to be_err
        expect(result.code).to eq(:workflow_source_missing)
      end
    end
  end
end
