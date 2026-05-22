# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/steps/api'

RSpec.describe Owl::Steps::Api, '.show' do
  def cli(argv, root)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s)
    [stdout.string, stderr.string]
  end

  def init(root)
    cli(['init', '--root', root.to_s], root)
  end

  def write_workflow_registry(root, key: 'feature')
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        #{key}:
          enabled: true
          source: "workflows/#{key}/workflow.yaml"
    YAML
  end

  def write_workflow_source(root, body, key: 'feature')
    write("#{root}/.owl/workflows/#{key}/workflow.yaml", body)
  end

  def write_spec_artifact_files(root)
    write("#{root}/.owl/artifacts.yaml", <<~YAML)
      schema_version: 1
      artifacts:
        spec:
          source: "artifacts/spec/artifact.yaml"
    YAML
    write("#{root}/.owl/artifacts/spec/artifact.yaml", <<~YAML)
      id: spec
      kind: markdown
      default_template: templates/default.md
      front_matter:
        type: object
        required: [status, summary]
        properties:
          status:
            type: string
            enum: [draft, approved]
      validation:
        required_sections:
          - Intent
          - Acceptance criteria
    YAML
    write(
      "#{root}/.owl/artifacts/spec/templates/default.md",
      "---\nstatus: draft\nsummary: t\n---\n\n## Intent\n\n## Acceptance criteria\n"
    )
  end

  def create_task(root)
    stdout, = cli(['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s, '--json'], root)
    JSON.parse(stdout).dig('task', 'id')
  end

  describe 'happy paths' do
    def setup_happy_path(root)
      init(root)
      write_workflow_registry(root)
      write_spec_artifact_files(root)
      write_workflow_source(root, <<~YAML)
        id: feature
        kind: feature
        artifacts:
          spec:
            type: spec
            storage:
              role: tasks
              path: "{{task.id}}/spec.md"
        steps:
          - id: brief
            title: Brief
            context: "Write the brief"
            creates: [spec]
      YAML
      create_task(root)
    end

    it 'returns a full bundle with inline context and resolved artifact_template' do
      with_tmp_project do |root|
        task_id = setup_happy_path(root)
        result = described_class.show(root: root, task_id: task_id, step_id: 'brief')

        expect(result).to be_ok
        bundle = result.value
        expect(bundle[:step]['id']).to eq('brief')
        expect(bundle[:step]['status']).to eq('pending')
        expect(bundle[:step]).not_to have_key('context')
        expect(bundle[:context]).to eq('Write the brief')
        expect(bundle[:artifact_template][:required_sections]).to eq(['Intent', 'Acceptance criteria'])
        expect(bundle[:artifact_template][:frontmatter_schema]).to include('type' => 'object')
        expect(bundle[:task]).to eq(id: task_id, title: 't', artifacts: {})
        expect(bundle[:overlays]).to eq([])
        expect(bundle[:execution_mode]).to be_nil
      end
    end

    it 'exposes default richer JSON contract on a minimal step' do
      with_tmp_project do |root|
        task_id = setup_happy_path(root)
        bundle = described_class.show(root: root, task_id: task_id, step_id: 'brief').value
        expect(bundle[:step]['title']).to eq('Brief')
        expect(bundle[:step]['session_type']).to eq('execution')
        expect(bundle[:step]['model_tier']).to eq('standard')
        expect(bundle[:step]['optional']).to be false
        expect(bundle[:step]['variants_keys']).to eq([])
      end
    end

    def write_richer_contract_workflow(root)
      write_workflow_source(root, <<~YAML)
        id: feature
        kind: feature
        artifacts:
          spec:
            type: spec
            storage: { role: tasks, path: "{{task.id}}/spec.md" }
        steps:
          - id: design
            title: Design discussion
            session_type: discussion
            tier: advanced
            optional: true
            context: "Design step"
            variants:
              short: { context_file: design.short.md }
              long:  { context_file: design.long.md }
            default_variant: short
      YAML
      write("#{root}/.owl/workflows/feature/design.short.md", 'short variant body')
      write("#{root}/.owl/workflows/feature/design.long.md", 'long variant body')
    end

    it 'exposes the full richer JSON contract in bundle[:step]' do
      with_tmp_project do |root|
        init(root)
        write_workflow_registry(root)
        write_spec_artifact_files(root)
        write_richer_contract_workflow(root)
        task_id = create_task(root)

        bundle = described_class.show(root: root, task_id: task_id, step_id: 'design').value
        expect(bundle[:step]['title']).to eq('Design discussion')
        expect(bundle[:step]['session_type']).to eq('discussion')
        expect(bundle[:step]['model_tier']).to eq('advanced')
        expect(bundle[:step]['optional']).to be true
        expect(bundle[:step]['variants_keys']).to eq(%w[long short])
      end
    end

    it 'reads context from context_file and exposes task artifact bodies when files exist' do
      with_tmp_project do |root|
        init(root)
        write_workflow_registry(root)
        write_spec_artifact_files(root)
        write("#{root}/.owl/workflows/feature/brief.context.md", 'Step context from file')
        write_workflow_source(root, <<~YAML)
          id: feature
          kind: feature
          artifacts:
            spec:
              type: spec
              storage:
                role: tasks
                path: "{{task.id}}/spec.md"
          steps:
            - id: brief
              context_file: "./brief.context.md"
              creates: [spec]
        YAML
        task_id = create_task(root)
        write("#{root}/tasks/#{task_id}/spec.md", 'spec body text')

        bundle = described_class.show(root: root, task_id: task_id, step_id: 'brief').value
        expect(bundle[:context]).to eq('Step context from file')
        expect(bundle[:task][:artifacts]).to eq('spec' => 'spec body text')
      end
    end

    it "marks step status as 'running' after Steps::Api.start" do
      with_tmp_project do |root|
        init(root)
        write_workflow_registry(root)
        write_workflow_source(root, <<~YAML)
          id: feature
          kind: feature
          artifacts: []
          steps:
            - id: a
        YAML
        task_id = create_task(root)
        described_class.start(root: root, task_id: task_id, step_id: 'a')

        bundle = described_class.show(root: root, task_id: task_id, step_id: 'a').value
        expect(bundle[:step]['status']).to eq('running')
      end
    end
  end

  describe 'optional fields' do
    it 'returns nil context when the step has neither context nor context_file' do
      with_tmp_project do |root|
        init(root)
        write_workflow_registry(root)
        write_workflow_source(root, <<~YAML)
          id: feature
          kind: feature
          artifacts: []
          steps:
            - id: a
        YAML
        task_id = create_task(root)

        bundle = described_class.show(root: root, task_id: task_id, step_id: 'a').value
        expect(bundle[:context]).to be_nil
      end
    end

    it 'returns nil artifact_template when the step has no creates list' do
      with_tmp_project do |root|
        init(root)
        write_workflow_registry(root)
        write_workflow_source(root, <<~YAML)
          id: feature
          kind: feature
          artifacts: []
          steps:
            - id: a
        YAML
        task_id = create_task(root)

        bundle = described_class.show(root: root, task_id: task_id, step_id: 'a').value
        expect(bundle[:artifact_template]).to be_nil
      end
    end

    it 'returns nil artifact_template when creates is an empty list' do
      with_tmp_project do |root|
        init(root)
        write_workflow_registry(root)
        write_workflow_source(root, <<~YAML)
          id: feature
          kind: feature
          artifacts: []
          steps:
            - id: a
              creates: []
        YAML
        task_id = create_task(root)

        bundle = described_class.show(root: root, task_id: task_id, step_id: 'a').value
        expect(bundle[:artifact_template]).to be_nil
      end
    end

    it 'returns empty artifacts hash when the workflow declares no artifacts' do
      with_tmp_project do |root|
        init(root)
        write_workflow_registry(root)
        write_workflow_source(root, <<~YAML)
          id: feature
          kind: feature
          artifacts: []
          steps:
            - id: a
        YAML
        task_id = create_task(root)

        bundle = described_class.show(root: root, task_id: task_id, step_id: 'a').value
        expect(bundle[:task][:artifacts]).to eq({})
      end
    end

    it 'omits artifacts whose files have not been written yet' do
      with_tmp_project do |root|
        init(root)
        write_workflow_registry(root)
        write_spec_artifact_files(root)
        write_workflow_source(root, <<~YAML)
          id: feature
          kind: feature
          artifacts:
            spec:
              type: spec
              storage:
                role: tasks
                path: "{{task.id}}/spec.md"
          steps:
            - id: a
        YAML
        task_id = create_task(root)

        bundle = described_class.show(root: root, task_id: task_id, step_id: 'a').value
        expect(bundle[:task][:artifacts]).to eq({})
      end
    end

    it 'exposes execution_mode and overlays for a step' do
      with_tmp_project do |root|
        init(root)
        write_workflow_registry(root)
        write_workflow_source(root, <<~YAML)
          id: feature
          kind: feature
          execution_mode: autonomous_after_brief
          artifacts: []
          steps:
            - id: a
        YAML
        write("#{root}/.owl/overlays/a.md", "Project conventions for step a.\n")
        task_id = create_task(root)

        bundle = described_class.show(root: root, task_id: task_id, step_id: 'a').value
        expect(bundle[:execution_mode]).to eq('autonomous_after_brief')
        expect(bundle[:overlays].first[:body]).to include('Project conventions')
      end
    end
  end

  describe 'step variants' do
    def setup_variant_project(root)
      init(root)
      write_workflow_registry(root)
      write_workflow_source(root, <<~YAML)
        id: feature
        kind: feature
        artifacts: []
        steps:
          - id: brief
            default_variant: feature
            variants:
              feature:
                context_file: brief.feature.context.md
              root_cause:
                context_file: brief.root_cause.context.md
      YAML
      write("#{root}/.owl/workflows/feature/brief.feature.context.md", "# Purpose\nfeature default\n")
      write("#{root}/.owl/workflows/feature/brief.root_cause.context.md", "# Purpose\nroot cause body\n")
    end

    it 'returns the chosen variant slug and its context body in the bundle' do
      with_tmp_project do |root|
        setup_variant_project(root)
        stdout, = cli(
          ['task', 'create', '--workflow', 'feature', '--title', 't',
           '--variant', 'brief=root_cause', '--root', root.to_s, '--json'],
          root
        )
        task_id = JSON.parse(stdout).dig('task', 'id')

        bundle = described_class.show(root: root, task_id: task_id, step_id: 'brief').value
        expect(bundle[:step]['variant']).to eq('root_cause')
        expect(bundle[:context]).to include('root cause body')
      end
    end

    it 'falls back to default_variant when the task has no variant fixed' do
      with_tmp_project do |root|
        setup_variant_project(root)
        stdout, = cli(
          ['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s, '--json'],
          root
        )
        task_id = JSON.parse(stdout).dig('task', 'id')

        bundle = described_class.show(root: root, task_id: task_id, step_id: 'brief').value
        expect(bundle[:step]['variant']).to eq('feature')
        expect(bundle[:context]).to include('feature default')
      end
    end
  end

  describe 'error propagation' do
    it 'propagates :task_not_found from Tasks::Api.inspect' do
      with_tmp_project do |root|
        init(root)
        write_workflow_registry(root)
        write_workflow_source(root, "id: feature\nkind: feature\nartifacts: []\nsteps:\n  - id: a\n")

        result = described_class.show(root: root, task_id: 'TASK-9999', step_id: 'a')
        expect(result).to be_err
        expect(result.code).to eq(:task_not_found)
      end
    end

    it 'returns :unknown_step_id when the step is not in the workflow' do
      with_tmp_project do |root|
        init(root)
        write_workflow_registry(root)
        write_workflow_source(root, "id: feature\nkind: feature\nartifacts: []\nsteps:\n  - id: a\n")
        task_id = create_task(root)

        result = described_class.show(root: root, task_id: task_id, step_id: 'missing')
        expect(result).to be_err
        expect(result.code).to eq(:unknown_step_id)
        expect(result.details[:step_id]).to eq('missing')
        expect(result.details[:task_id]).to eq(task_id)
      end
    end

    it 'propagates :step_context_conflict when a step declares both context and context_file' do
      with_tmp_project do |root|
        init(root)
        write_workflow_registry(root)
        write_workflow_source(root, <<~YAML)
          id: feature
          kind: feature
          artifacts: []
          steps:
            - id: a
              context: "inline"
              context_file: "./somewhere.md"
        YAML
        task_id = create_task(root)

        result = described_class.show(root: root, task_id: task_id, step_id: 'a')
        expect(result).to be_err
        expect(result.code).to eq(:step_context_conflict)
      end
    end
  end
end
