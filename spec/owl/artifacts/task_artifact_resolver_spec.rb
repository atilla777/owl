# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/artifacts/api'
require 'owl/cli/api'

RSpec.describe Owl::Artifacts::Api, '.resolve' do # rubocop:disable RSpec/MultipleDescribes
  def init_project(root)
    Owl::Cli::Api.run(
      argv: ['init', '--root', root.to_s],
      stdout: StringIO.new, stderr: StringIO.new, env: {}, cwd: root.to_s
    )
  end

  def seed_workflow(root, body)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", body)
  end

  def seed_artifact_registry(root, body)
    write("#{root}/.owl/artifacts.yaml", body)
  end

  def create_task(root)
    stdout = StringIO.new
    Owl::Cli::Api.run(
      argv: ['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s, '--json'],
      stdout: stdout, stderr: StringIO.new, env: {}, cwd: root.to_s
    )
    JSON.parse(stdout.string).dig('task', 'id')
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
        specs:
          type: spec
          multiple: true
          storage:
            role: tasks
            path: "{{task.id}}/specs/**/*.md"
      steps:
        - id: brief
          creates: [brief]
        - id: specify
          requires: [brief]
          creates: [specs]
    YAML
  end

  def seed_full_project(root)
    init_project(root)
    seed_workflow(root, base_workflow_yaml)
    seed_artifact_registry(root, <<~YAML)
      schema_version: 1
      artifacts:
        brief:
          source: "artifacts/brief/artifact.yaml"
        spec:
          source: "artifacts/spec/artifact.yaml"
    YAML
    write("#{root}/.owl/artifacts/brief/artifact.yaml", <<~YAML)
      id: brief
      title: Feature brief
      kind: markdown
      default_template: templates/default.md
      validation:
        required_sections:
          - Context
    YAML
    write("#{root}/.owl/artifacts/brief/templates/default.md", "# Brief\n\n## Context\n")
    write("#{root}/.owl/artifacts/spec/artifact.yaml", <<~YAML)
      id: spec
      title: Domain spec
      kind: markdown
    YAML
    create_task(root)
  end

  it 'returns absolute path, template URI, and validation rules for an existing artifact' do
    with_tmp_project do |root|
      task_id = seed_full_project(root)
      write("#{root}/tasks/#{task_id}/brief.md", "# Brief\n")

      result = described_class.resolve(root: root, task_id: task_id, artifact_key: 'brief')
      expect(result).to be_ok
      value = result.value
      expect(value[:path]).to eq("#{root}/tasks/#{task_id}/brief.md")
      expect(value[:uri]).to eq("file://#{root}/tasks/#{task_id}/brief.md")
      expect(value[:exists]).to be(true)
      expect(value[:template_uri]).to eq("file://#{root}/.owl/artifacts/brief/templates/default.md")
      expect(value[:template_present]).to be(true)
      expect(value[:validation]).to eq('required_sections' => ['Context'])
    end
  end

  it 'returns planned path and template metadata when the artifact file does not exist' do
    with_tmp_project do |root|
      task_id = seed_full_project(root)

      result = described_class.resolve(root: root, task_id: task_id, artifact_key: 'brief')
      expect(result).to be_ok
      value = result.value
      expect(value[:exists]).to be(false)
      expect(value[:path]).to eq("#{root}/tasks/#{task_id}/brief.md")
      expect(value[:template_present]).to be(true)
    end
  end

  it 'exposes multiple: true and the glob path template for multi-artifacts' do
    with_tmp_project do |root|
      task_id = seed_full_project(root)

      result = described_class.resolve(root: root, task_id: task_id, artifact_key: 'specs')
      expect(result).to be_ok
      expect(result.value[:multiple]).to be(true)
      expect(result.value[:storage_path_template]).to eq('{{task.id}}/specs/**/*.md')
    end
  end

  it 'returns unknown_workflow_artifact when the key is not declared on the workflow' do
    with_tmp_project do |root|
      task_id = seed_full_project(root)
      result = described_class.resolve(root: root, task_id: task_id, artifact_key: 'nope')
      expect(result).to be_err
      expect(result.code).to eq(:unknown_workflow_artifact)
    end
  end

  it 'returns unknown_artifact_type when the type is not in the registry' do
    with_tmp_project do |root|
      init_project(root)
      seed_workflow(root, base_workflow_yaml)
      seed_artifact_registry(root, "schema_version: 1\nartifacts: {}\n")
      task_id = create_task(root)

      result = described_class.resolve(root: root, task_id: task_id, artifact_key: 'brief')
      expect(result).to be_err
      expect(result.code).to eq(:unknown_artifact_type)
    end
  end

  it 'returns unknown_role when the workflow points at a role missing in the active profile' do
    with_tmp_project do |root|
      init_project(root)
      seed_workflow(root, <<~YAML)
        id: feature
        kind: task
        artifacts:
          brief:
            type: brief
            storage:
              role: missing_role
              path: "{{task.id}}/brief.md"
        steps:
          - id: brief
      YAML
      seed_artifact_registry(root, <<~YAML)
        schema_version: 1
        artifacts:
          brief:
            source: "artifacts/brief/artifact.yaml"
      YAML
      write("#{root}/.owl/artifacts/brief/artifact.yaml", "id: brief\nkind: markdown\n")
      task_id = create_task(root)

      result = described_class.resolve(root: root, task_id: task_id, artifact_key: 'brief')
      expect(result).to be_err
      expect(result.code).to eq(:unknown_role)
    end
  end

  it 'returns workflow_artifact_storage_missing when storage.role is absent' do
    with_tmp_project do |root|
      init_project(root)
      seed_workflow(root, <<~YAML)
        id: feature
        kind: task
        artifacts:
          brief:
            type: brief
            storage:
              path: "{{task.id}}/brief.md"
        steps:
          - id: brief
      YAML
      seed_artifact_registry(root, <<~YAML)
        schema_version: 1
        artifacts:
          brief:
            source: "artifacts/brief/artifact.yaml"
      YAML
      write("#{root}/.owl/artifacts/brief/artifact.yaml", "id: brief\nkind: markdown\n")
      task_id = create_task(root)

      result = described_class.resolve(root: root, task_id: task_id, artifact_key: 'brief')
      expect(result).to be_err
      expect(result.code).to eq(:workflow_artifact_storage_missing)
    end
  end
end

RSpec.describe Owl::Artifacts::Api, '.find' do
  it 'returns the artifact type loader payload when the type is registered' do
    with_tmp_project do |root|
      write("#{root}/.owl/artifacts.yaml", <<~YAML)
        schema_version: 1
        artifacts:
          spec:
            source: "artifacts/spec/artifact.yaml"
      YAML
      write("#{root}/.owl/artifacts/spec/artifact.yaml", <<~YAML)
        id: spec
        title: Domain spec
        kind: markdown
      YAML

      result = described_class.find(root: root, key: 'spec')
      expect(result).to be_ok
      expect(result.value[:type]).to eq('spec')
      expect(result.value[:title]).to eq('Domain spec')
    end
  end

  it 'returns unknown_artifact_type for an unknown key and lists available keys' do
    with_tmp_project do |root|
      write("#{root}/.owl/artifacts.yaml", <<~YAML)
        schema_version: 1
        artifacts:
          brief:
            source: "artifacts/brief/artifact.yaml"
          spec:
            source: "artifacts/spec/artifact.yaml"
      YAML
      result = described_class.find(root: root, key: 'missing')
      expect(result).to be_err
      expect(result.code).to eq(:unknown_artifact_type)
      expect(result.details[:available]).to contain_exactly('brief', 'spec')
    end
  end

  it 'returns artifact_type_source_missing when the source file is not present' do
    with_tmp_project do |root|
      write("#{root}/.owl/artifacts.yaml", <<~YAML)
        schema_version: 1
        artifacts:
          spec:
            source: "artifacts/spec/artifact.yaml"
      YAML

      result = described_class.find(root: root, key: 'spec')
      expect(result).to be_err
      expect(result.code).to eq(:artifact_type_source_missing)
    end
  end

  it 'propagates registry errors when the registry file is missing' do
    with_tmp_project do |root|
      result = described_class.find(root: root, key: 'spec')
      expect(result).to be_err
      expect(result.code).to eq(:artifacts_registry_missing)
    end
  end
end
