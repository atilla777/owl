# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'
require 'owl/validation/api'

RSpec.describe Owl::Validation::Api do
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
      title: Brief
      kind: markdown
      validation:
        required_sections:
          - Summary
        required_patterns:
          - pattern: "### Item:"
            level: error
            description: "Each brief must list at least one item."
          - pattern: "Notes"
            type: substring
            level: warning
            description: "Brief should include notes."
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
    Owl::Cli::Api.run(argv: ['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s, '--json'],
                      stdout: stdout, stderr: StringIO.new, env: {}, cwd: root.to_s)
    JSON.parse(stdout.string).dig('task', 'id')
  end

  describe '.artifact' do
    it 'returns valid: false with a missing_artifact violation when file does not exist' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        result = described_class.artifact(root: root, task_id: task_id, artifact_key: 'brief')
        expect(result).to be_ok
        expect(result.value[:valid]).to be(false)
        expect(result.value[:violations].first[:type]).to eq('missing_artifact')
      end
    end

    it 'returns valid: true for an artifact that satisfies required sections and patterns' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        write("#{root}/tasks/#{task_id}/brief.md", <<~MD)
          # Brief

          ## Summary

          ### Item: foo

          Notes go here.
        MD
        result = described_class.artifact(root: root, task_id: task_id, artifact_key: 'brief')
        expect(result).to be_ok
        expect(result.value[:valid]).to be(true)
        expect(result.value[:violations]).to be_empty
      end
    end

    it 'records missing_section violations case-sensitively' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        write("#{root}/tasks/#{task_id}/brief.md", <<~MD)
          # Brief

          ## summary

          ### Item: foo

          Notes
        MD
        result = described_class.artifact(root: root, task_id: task_id, artifact_key: 'brief')
        expect(result.value[:valid]).to be(false)
        types = result.value[:violations].map { |v| v[:type] }
        expect(types).to include('missing_section')
        expect(result.value[:violations].find { |v| v[:type] == 'missing_section' }[:section]).to eq('Summary')
      end
    end

    it 'records missing_pattern as error and warning according to level' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        write("#{root}/tasks/#{task_id}/brief.md", "# Brief\n\n## Summary\n")
        result = described_class.artifact(root: root, task_id: task_id, artifact_key: 'brief')
        levels = result.value[:violations].select { |v| v[:type] == 'missing_pattern' }.map { |v| v[:level] }
        expect(levels).to include('error')
        expect(levels).to include('warning')
        expect(result.value[:valid]).to be(false)
      end
    end

    it 'stays valid when only warnings are reported' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        write("#{root}/tasks/#{task_id}/brief.md", <<~MD)
          # Brief

          ## Summary

          ### Item: foo
        MD
        result = described_class.artifact(root: root, task_id: task_id, artifact_key: 'brief')
        expect(result.value[:valid]).to be(true)
        warnings = result.value[:violations].select { |v| v[:level] == 'warning' }
        expect(warnings).not_to be_empty
      end
    end

    it 'reports front_matter_missing when schema declares required keys and front matter is absent' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        write("#{root}/tasks/#{task_id}/spec.md", "# Spec\n")
        result = described_class.artifact(root: root, task_id: task_id, artifact_key: 'spec')
        types = result.value[:violations].map { |v| v[:type] }
        expect(types).to include('front_matter_missing')
      end
    end

    it 'reports front_matter_invalid for missing required keys' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        write("#{root}/tasks/#{task_id}/spec.md", <<~MD)
          ---
          status: draft
          ---

          # Spec
        MD
        result = described_class.artifact(root: root, task_id: task_id, artifact_key: 'spec')
        missing = result.value[:violations].find { |v| v[:type] == 'front_matter_invalid' && v[:field] == 'summary' }
        expect(missing).not_to be_nil
      end
    end

    it 'reports front_matter_invalid when enum value is not allowed' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        write("#{root}/tasks/#{task_id}/spec.md", <<~MD)
          ---
          status: rejected
          summary: ok
          ---

          # Spec
        MD
        result = described_class.artifact(root: root, task_id: task_id, artifact_key: 'spec')
        enum_violation = result.value[:violations].find do |v|
          v[:type] == 'front_matter_invalid' && v[:field] == 'status'
        end
        expect(enum_violation[:description]).to include('rejected')
      end
    end

    it 'reports front_matter_invalid when type does not match' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        write("#{root}/tasks/#{task_id}/spec.md", <<~MD)
          ---
          status: draft
          summary: 123
          ---

          # Spec
        MD
        result = described_class.artifact(root: root, task_id: task_id, artifact_key: 'spec')
        type_violation = result.value[:violations].find do |v|
          v[:type] == 'front_matter_invalid' && v[:field] == 'summary'
        end
        expect(type_violation[:description]).to include("type 'string'")
      end
    end

    it 'reports front_matter_parse_error on malformed YAML' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        write("#{root}/tasks/#{task_id}/spec.md", "---\n: : :\n---\n\n# Spec\n")
        result = described_class.artifact(root: root, task_id: task_id, artifact_key: 'spec')
        expect(result.value[:violations].first[:type]).to eq('front_matter_parse_error')
      end
    end

    it 'returns Err for an unknown artifact key' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        result = described_class.artifact(root: root, task_id: task_id, artifact_key: 'nope')
        expect(result).to be_err
        expect(result.code).to eq(:unknown_workflow_artifact)
      end
    end

    it 'accepts a passing front matter without trailing newline after closing fence' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        write("#{root}/tasks/#{task_id}/spec.md", "---\nstatus: draft\nsummary: ok\n---")
        result = described_class.artifact(root: root, task_id: task_id, artifact_key: 'spec')
        expect(result.value[:valid]).to be(true)
      end
    end
  end

  describe 'semantic validation opt-in keys' do
    def enable_semantic_brief(root, validation_yaml)
      write("#{root}/.owl/artifacts/brief/artifact.yaml", <<~YAML)
        id: brief
        title: Brief
        kind: markdown
        validation:
        #{validation_yaml.gsub(/^/, '  ')}
      YAML
    end

    it 'surfaces all four new blocking violation types when the keys are declared' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        enable_semantic_brief(root, <<~YAML)
          forbid_empty_sections: true
          forbid_placeholders: true
          require_scenarios: true
          require_when_then: true
        YAML
        write("#{root}/tasks/#{task_id}/brief.md", <<~MD)
          ## Summary

          Filled.

          ## Empty

          ### Requirement: NoScenario

          just prose with a TODO marker

          ### Requirement: HasScenario

          #### Scenario: half
          - WHEN it happens
        MD
        result = described_class.artifact(root: root, task_id: task_id, artifact_key: 'brief')
        types = result.value[:violations].map { |v| v[:type] }
        expect(types).to include('empty_section', 'placeholder_text', 'requirement_without_scenario',
                                 'scenario_missing_clause')
        expect(result.value[:valid]).to be(false)
        expect(result.value[:violations].all? { |v| v[:level] == 'error' }).to be(true)
      end
    end

    it 'passes when the declared semantic rules are all satisfied' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        enable_semantic_brief(root, <<~YAML)
          required_sections:
            - Summary
          forbid_empty_sections: true
          forbid_placeholders: true
          require_scenarios: true
          require_when_then: true
        YAML
        write("#{root}/tasks/#{task_id}/brief.md", <<~MD)
          ## Summary

          All clear here.

          ### Requirement: Solid

          This requirement is described here.

          #### Scenario: full
          - WHEN it happens
          - THEN it works
        MD
        result = described_class.artifact(root: root, task_id: task_id, artifact_key: 'brief')
        expect(result.value[:valid]).to be(true)
        expect(result.value[:violations]).to be_empty
      end
    end

    it 'leaves behaviour unchanged for an artifact type that declares none of the new keys' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        enable_semantic_brief(root, <<~YAML)
          required_sections:
            - Summary
        YAML
        write("#{root}/tasks/#{task_id}/brief.md", <<~MD)
          ## Summary

          ## Empty section that would fail forbid_empty_sections

          TODO leftover marker
        MD
        result = described_class.artifact(root: root, task_id: task_id, artifact_key: 'brief')
        expect(result.value[:valid]).to be(true)
        expect(result.value[:violations]).to be_empty
      end
    end
  end

  describe '.task' do
    it 'aggregates results across all workflow artifacts and reports all_valid' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        write("#{root}/tasks/#{task_id}/brief.md", <<~MD)
          ## Summary

          ### Item: x

          Notes
        MD
        write("#{root}/tasks/#{task_id}/spec.md", <<~MD)
          ---
          status: draft
          summary: ok
          ---

          # Spec
        MD
        result = described_class.task(root: root, task_id: task_id)
        expect(result).to be_ok
        expect(result.value[:all_valid]).to be(true)
        keys = result.value[:results].map { |r| r[:artifact_key] }
        expect(keys).to contain_exactly('brief', 'spec')
      end
    end

    it 'isolates invalid artifacts so others still report' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        write("#{root}/tasks/#{task_id}/brief.md", "## Summary\n\n### Item: x\n\nNotes\n")
        result = described_class.task(root: root, task_id: task_id)
        expect(result.value[:all_valid]).to be(false)
        brief = result.value[:results].find { |r| r[:artifact_key] == 'brief' }
        spec = result.value[:results].find { |r| r[:artifact_key] == 'spec' }
        expect(brief[:valid]).to be(true)
        expect(spec[:valid]).to be(false)
      end
    end

    it 'returns Err with task_not_found for unknown task' do
      with_tmp_project do |root|
        seed_full_project(root)
        result = described_class.task(root: root, task_id: 'TASK-9999')
        expect(result).to be_err
        expect(result.code).to eq(:task_not_found)
      end
    end

    it 'returns Err when the workflow source is missing' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        File.delete("#{root}/.owl/workflows/feature/workflow.yaml")
        result = described_class.task(root: root, task_id: task_id)
        expect(result).to be_err
        expect(result.code).to eq(:workflow_source_missing)
      end
    end

    it 'records resolution_error entries when an artifact key cannot be resolved' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
          id: feature
          kind: task
          artifacts:
            brief:
              type: brief
              storage:
                role: tasks
                path: "{{task.id}}/brief.md"
            ghost:
              type: missing_type
              storage:
                role: tasks
                path: "{{task.id}}/ghost.md"
          steps:
            - id: brief
              creates: [brief]
        YAML
        result = described_class.task(root: root, task_id: task_id)
        ghost = result.value[:results].find { |r| r[:artifact_key] == 'ghost' }
        expect(ghost[:valid]).to be(false)
        expect(ghost[:violations].first[:type]).to eq('resolution_error')
      end
    end

    it 'returns task_workflow_missing when task.yaml lacks workflow key' do
      with_tmp_project do |root|
        task_id = seed_full_project(root)
        task_path = "#{root}/tasks/#{task_id}/task.yaml"
        payload = YAML.safe_load_file(task_path, permitted_classes: [Date, Time], aliases: false)
        payload.delete('workflow')
        write(task_path, YAML.dump(payload))
        result = described_class.task(root: root, task_id: task_id)
        expect(result).to be_err
        expect(result.code).to eq(:task_workflow_missing)
      end
    end
  end
end
