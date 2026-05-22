# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/workflows/backend'
require 'owl/workflows/backends/filesystem'
require 'owl/cli/api'

RSpec.describe Owl::Workflows::Backends::Filesystem do
  def seed_feature_registry(root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
          version: "1.0"
    YAML
  end

  def seed_feature_source(root)
    write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
      id: feature
      kind: task
      title: Feature
      artifacts: {}
      steps:
        - id: a
          session_type: discussion
        - id: b
          session_type: discussion
          requires: [a]
    YAML
  end

  def init_project(root)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: ['init', '--root', root.to_s], stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s)
  end

  it 'includes the Owl::Workflows::Backend contract' do
    expect(described_class.included_modules).to include(Owl::Workflows::Backend)
  end

  describe 'instance contract' do
    it 'responds to every method declared by Owl::Workflows::Backend' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)
        Owl::Workflows::Backend.instance_methods(false).each do |method_name|
          expect(backend).to respond_to(method_name), "missing backend method: #{method_name}"
        end
      end
    end
  end

  describe '#registry' do
    it 'returns Ok with parsed registry entries when .owl/workflows.yaml exists' do
      with_tmp_project do |root|
        seed_feature_registry(root)
        backend = described_class.new(root: root)
        result = backend.registry
        expect(result).to be_ok
        expect(result.value[:entries].map { |e| e[:key] }).to eq(['feature'])
      end
    end

    it 'returns Err when registry file is missing' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)
        result = backend.registry
        expect(result).to be_err
        expect(result.code).to eq(:workflows_registry_missing)
      end
    end
  end

  describe '#list' do
    it 'returns the registered workflows with present-source metadata' do
      with_tmp_project do |root|
        seed_feature_registry(root)
        seed_feature_source(root)
        backend = described_class.new(root: root)
        result = backend.list
        expect(result).to be_ok
        expect(result.value.first[:key]).to eq('feature')
        expect(result.value.first[:source_present]).to be(true)
      end
    end
  end

  describe '#find' do
    it 'returns Ok with entry and source body for a registered key' do
      with_tmp_project do |root|
        seed_feature_registry(root)
        seed_feature_source(root)
        backend = described_class.new(root: root)
        result = backend.find(key: 'feature')
        expect(result).to be_ok
        expect(result.value[:entry][:key]).to eq('feature')
        expect(result.value[:source][:body]['id']).to eq('feature')
      end
    end

    it 'returns Err(:unknown_workflow) for a missing key' do
      with_tmp_project do |root|
        seed_feature_registry(root)
        backend = described_class.new(root: root)
        result = backend.find(key: 'nope')
        expect(result).to be_err
        expect(result.code).to eq(:unknown_workflow)
      end
    end
  end

  describe '#scaffold' do
    it 'writes the minimal seed for a new id' do
      with_tmp_project do |root|
        seed_feature_registry(root)
        backend = described_class.new(root: root)
        result = backend.scaffold(id: 'fresh', kind: 'task')
        expect(result).to be_ok
        expect(File.exist?(result.value[:path])).to be(true)
      end
    end

    it 'rejects an invalid id without writing' do
      with_tmp_project do |root|
        seed_feature_registry(root)
        backend = described_class.new(root: root)
        result = backend.scaffold(id: 'Bad-Id', kind: 'task')
        expect(result).to be_err
        expect(result.code).to eq(:invalid_workflow_id)
      end
    end
  end

  describe '#validate' do
    it 'validates a registered workflow by id' do
      with_tmp_project do |root|
        seed_feature_registry(root)
        seed_feature_source(root)
        backend = described_class.new(root: root)
        result = backend.validate(id_or_path: 'feature')
        expect(result).to be_ok
        expect(result.value[:valid]).to be(true)
      end
    end

    it 'reports :workflow_source_missing for a missing file path' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)
        result = backend.validate(id_or_path: "#{root}/nope/workflow.yaml")
        expect(result).to be_err
        expect(result.code).to eq(:workflow_source_missing)
      end
    end
  end

  describe '#graph' do
    it 'returns the topological order of a linear workflow' do
      with_tmp_project do |root|
        seed_feature_registry(root)
        seed_feature_source(root)
        backend = described_class.new(root: root)
        result = backend.graph(workflow_key: 'feature')
        expect(result).to be_ok
        expect(result.value[:order]).to eq(%w[a b])
      end
    end

    it 'reports :workflow_source_missing when the source is absent' do
      with_tmp_project do |root|
        seed_feature_registry(root)
        backend = described_class.new(root: root)
        result = backend.graph(workflow_key: 'feature')
        expect(result).to be_err
        expect(result.code).to eq(:workflow_source_missing)
      end
    end
  end

  describe '#definition' do
    it 'returns body, normalized steps, graph and artifacts' do
      with_tmp_project do |root|
        seed_feature_registry(root)
        seed_feature_source(root)
        backend = described_class.new(root: root)
        result = backend.definition(workflow_key: 'feature')
        expect(result).to be_ok
        expect(result.value[:key]).to eq('feature')
        expect(result.value[:steps].keys).to eq(%w[a b])
        expect(result.value[:graph][:order]).to eq(%w[a b])
      end
    end

    it 'accepts an injected backend for resolving step context' do
      with_tmp_project do |root|
        seed_feature_registry(root)
        write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
          id: feature
          kind: task
          steps:
            - id: a
              context_file: a.context.md
        YAML
        stub_backend = Class.new do
          def read_step_context(step_id:, **)
            Owl::Result.ok("stub for #{step_id}")
          end
        end.new
        backend = described_class.new(root: root)
        result = backend.definition(workflow_key: 'feature', backend: stub_backend)
        expect(result).to be_ok
        expect(result.value[:steps]['a']['context']).to eq('stub for a')
      end
    end
  end

  describe '#ready_steps' do
    it 'returns the initial ready set for a freshly created task' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_registry(root)
        seed_feature_source(root)

        stdout = StringIO.new
        stderr = StringIO.new
        Owl::Cli::Api.run(
          argv: ['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s, '--json'],
          stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s
        )
        task_id = JSON.parse(stdout.string).dig('task', 'id')

        backend = described_class.new(root: root)
        result = backend.ready_steps(task_id: task_id)
        expect(result).to be_ok
        expect(result.value[:ready].map { |s| s[:id] }).to eq(['a'])
      end
    end

    it 'reports :task_not_found when the task does not exist' do
      with_tmp_project do |root|
        init_project(root)
        seed_feature_registry(root)
        seed_feature_source(root)
        backend = described_class.new(root: root)
        result = backend.ready_steps(task_id: 'TASK-9999')
        expect(result).to be_err
        expect(result.code).to eq(:task_not_found)
      end
    end
  end

  describe '#read_step_context' do
    it 'returns Ok with file contents when context_file exists inside the workflow source directory' do
      with_tmp_project do |root|
        source_dir = "#{root}/.owl/workflows/feature"
        write("#{source_dir}/specify.context.md", 'hello from file')
        backend = described_class.new(root: root)

        result = backend.read_step_context(
          source_dir: source_dir,
          step_id: 'specify',
          relative_path: 'specify.context.md'
        )

        expect(result).to be_ok
        expect(result.value).to eq('hello from file')
      end
    end

    it 'returns :step_context_file_not_found when the relative file is missing' do
      with_tmp_project do |root|
        source_dir = "#{root}/.owl/workflows/feature"
        FileUtils.mkdir_p(source_dir)
        backend = described_class.new(root: root)

        result = backend.read_step_context(
          source_dir: source_dir,
          step_id: 'specify',
          relative_path: 'missing.context.md'
        )

        expect(result).to be_err
        expect(result.code).to eq(:step_context_file_not_found)
        expect(result.details).to include(step_id: 'specify', relative_path: 'missing.context.md')
        expect(result.details[:resolved_path]).to end_with('/.owl/workflows/feature/missing.context.md')
      end
    end

    it 'returns :step_context_path_escape when the relative path uses ..' do
      with_tmp_project do |root|
        source_dir = "#{root}/.owl/workflows/feature"
        FileUtils.mkdir_p(source_dir)
        backend = described_class.new(root: root)

        result = backend.read_step_context(
          source_dir: source_dir,
          step_id: 'specify',
          relative_path: '../other/secret.md'
        )

        expect(result).to be_err
        expect(result.code).to eq(:step_context_path_escape)
        expect(result.details).to eq(step_id: 'specify', relative_path: '../other/secret.md')
      end
    end

    it 'returns :step_context_path_escape when the relative path is absolute' do
      with_tmp_project do |root|
        source_dir = "#{root}/.owl/workflows/feature"
        FileUtils.mkdir_p(source_dir)
        backend = described_class.new(root: root)

        result = backend.read_step_context(
          source_dir: source_dir,
          step_id: 'specify',
          relative_path: '/etc/passwd'
        )

        expect(result).to be_err
        expect(result.code).to eq(:step_context_path_escape)
      end
    end
  end

  describe '#seeded_sources' do
    it 'returns workflow source YAMLs plus per-step .context.md files' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)
        sources = backend.seeded_sources
        workflow_files = sources.select { |f| f[:relative_path].end_with?('/workflow.yaml') }
        expect(workflow_files.map { |f| f[:relative_path] }).to include(
          '.owl/workflows/feature/workflow.yaml',
          '.owl/workflows/composite_feature/workflow.yaml'
        )
      end
    end
  end

  describe '#default_template' do
    it 'returns a parseable YAML registry with seeded workflow entries' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)
        parsed = YAML.safe_load(backend.default_template)
        expect(parsed['workflows'].keys).to contain_exactly('feature', 'composite_feature')
        expect(parsed['default_workflow']).to eq('feature')
        expect(parsed['schema_version']).to eq(1)
      end
    end
  end
end
