# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'
require 'owl/instructions/api'

RSpec.describe Owl::Instructions::Api do
  def cli(argv, root)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s)
    [stdout.string, stderr.string]
  end

  def init_project(root)
    cli(['init', '--root', root.to_s], root)
  end

  def write_skill(root, skill_id, body)
    write("#{root}/.claude/skills/#{skill_id}/SKILL.md", body)
  end

  def write_command(root, skill_id, body)
    write("#{root}/.claude/commands/#{skill_id}.md", body)
  end

  def seed_two_step_workflow(root)
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
          skill: owl-step-discussion
          session_type: discussion
        - id: b
          skill: owl-step-discussion
          session_type: discussion
          requires: ["a"]
      artifacts: []
    YAML
  end

  def create_feature_task(root)
    cli(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s], root)
    'TASK-0001'
  end

  describe '.read_skill' do
    it 'returns skill path, command_path and the first non-heading paragraph as summary' do
      with_tmp_project do |root|
        write_skill(root, 'owl-step-foo', <<~MD)
          ---
          name: owl-step-foo
          description: Foo skill.
          ---

          Foo step does foo work. Triggered when bar.

          ## Purpose

          Some purpose text.
        MD
        write_command(root, 'owl-step-foo', "# command\n")

        result = described_class.read_skill(root: root, skill_id: 'owl-step-foo')

        expect(result).to be_ok
        expect(result.value[:skill][:id]).to eq('owl-step-foo')
        expect(result.value[:skill][:path]).to end_with('.claude/skills/owl-step-foo/SKILL.md')
        expect(result.value[:skill][:command_path]).to end_with('.claude/commands/owl-step-foo.md')
        expect(result.value[:summary]).to eq('Foo step does foo work. Triggered when bar.')
      end
    end

    it 'returns nil command_path when the slash-command file is absent' do
      with_tmp_project do |root|
        write_skill(root, 'owl-step-bar', "---\nname: owl-step-bar\n---\n\nBody text.\n")

        result = described_class.read_skill(root: root, skill_id: 'owl-step-bar')

        expect(result).to be_ok
        expect(result.value[:skill][:command_path]).to be_nil
      end
    end

    it 'returns empty summary when SKILL.md only has front-matter and headings' do
      with_tmp_project do |root|
        write_skill(root, 'owl-step-empty', <<~MD)
          ---
          name: owl-step-empty
          ---

          ## Purpose

          ## When to use
        MD

        result = described_class.read_skill(root: root, skill_id: 'owl-step-empty')

        expect(result).to be_ok
        expect(result.value[:summary]).to eq('')
      end
    end

    it 'returns :skill_not_found when SKILL.md does not exist' do
      with_tmp_project do |root|
        result = described_class.read_skill(root: root, skill_id: 'owl-step-missing')

        expect(result).to be_err
        expect(result.code).to eq(:skill_not_found)
      end
    end
  end

  describe '.build_payload' do
    it 'resolves the current task pointer when task_id is not supplied' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_workflow(root)
        task_id = create_feature_task(root)
        cli(['task', 'use', task_id, '--root', root.to_s], root)

        result = described_class.build_payload(root: root)

        expect(result).to be_ok
        body = result.value
        expect(body[:ok]).to be(true)
        expect(body.dig(:task, :id)).to eq(task_id)
        expect(body.dig(:task, :workflow_key)).to eq('feature')
        expect(body.dig(:step, :id)).to eq('a')
        expect(body.dig(:skill, :id)).to eq('owl-step-discussion')
        expect(body[:summary]).to be_a(String)
        expect(body[:invocation]).to include(:task, :step, :inputs, :outputs)
      end
    end

    it 'uses the explicit task_id and step_id when supplied' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_workflow(root)
        task_id = create_feature_task(root)
        cli(['step', 'start', task_id, 'a', '--root', root.to_s], root)
        cli(['step', 'complete', task_id, 'a', '--root', root.to_s], root)

        result = described_class.build_payload(root: root, task_id: task_id, step_id: 'b')

        expect(result).to be_ok
        expect(result.value.dig(:step, :id)).to eq('b')
      end
    end

    it 'returns :no_current_task when the pointer is empty and no task_id is supplied' do
      with_tmp_project do |root|
        init_project(root)
        seed_two_step_workflow(root)

        result = described_class.build_payload(root: root)

        expect(result).to be_err
        expect(result.code).to eq(:no_current_task)
      end
    end

    it 'returns :no_ready_steps when every step is already done' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/.owl/workflows.yaml", <<~YAML)
          schema_version: 1
          workflows:
            tiny:
              enabled: true
              source: "workflows/tiny/workflow.yaml"
        YAML
        write("#{root}/.owl/workflows/tiny/workflow.yaml", <<~YAML)
          id: tiny
          kind: task
          steps:
            - id: only
              skill: owl-step-discussion
              session_type: discussion
          artifacts: []
        YAML
        cli(['task', 'create', '--workflow', 'tiny', '--title', 't', '--root', root.to_s], root)
        cli(['step', 'start', 'TASK-0001', 'only', '--root', root.to_s], root)
        cli(['step', 'complete', 'TASK-0001', 'only', '--root', root.to_s], root)

        result = described_class.build_payload(root: root, task_id: 'TASK-0001')

        expect(result).to be_err
        expect(result.code).to eq(:no_ready_steps)
      end
    end

    it 'returns :step_skill_missing when the workflow step has no skill id' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/.owl/workflows.yaml", <<~YAML)
          schema_version: 1
          workflows:
            bare:
              enabled: true
              source: "workflows/bare/workflow.yaml"
        YAML
        write("#{root}/.owl/workflows/bare/workflow.yaml", <<~YAML)
          id: bare
          kind: task
          steps:
            - id: only
          artifacts: []
        YAML
        cli(['task', 'create', '--workflow', 'bare', '--title', 't', '--root', root.to_s], root)

        result = described_class.build_payload(root: root, task_id: 'TASK-0001')

        expect(result).to be_err
        expect(result.code).to eq(:step_skill_missing)
      end
    end

    it 'propagates :skill_not_found when the step skill is not materialized' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/.owl/workflows.yaml", <<~YAML)
          schema_version: 1
          workflows:
            phantom:
              enabled: true
              source: "workflows/phantom/workflow.yaml"
        YAML
        write("#{root}/.owl/workflows/phantom/workflow.yaml", <<~YAML)
          id: phantom
          kind: task
          steps:
            - id: only
              skill: owl-step-phantom-never-shipped
          artifacts: []
        YAML
        cli(['task', 'create', '--workflow', 'phantom', '--title', 't', '--root', root.to_s], root)

        result = described_class.build_payload(root: root, task_id: 'TASK-0001')

        expect(result).to be_err
        expect(result.code).to eq(:skill_not_found)
      end
    end
  end
end
