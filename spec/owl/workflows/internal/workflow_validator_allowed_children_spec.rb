# frozen_string_literal: true

require 'yaml'

require 'owl/workflows/internal/workflow_validator'

RSpec.describe Owl::Workflows::Internal::WorkflowValidator, '.validate allowed_children' do
  def call(body, root: nil)
    described_class.validate(root: root, body: body, source_path: nil)
  end

  let(:composite_body) do
    {
      'id' => 'parent_wf',
      'kind' => 'composite_task',
      'title' => 'Parent',
      'artifacts' => {},
      'steps' => []
    }
  end

  let(:task_body) do
    {
      'id' => 'leaf_wf',
      'kind' => 'task',
      'title' => 'Leaf',
      'artifacts' => {},
      'steps' => []
    }
  end

  it 'accepts a composite body without allowed_children (permissive default)' do
    expect(call(composite_body)).to be_ok
  end

  it 'rejects allowed_children given as a scalar string (ac-1)' do
    body = composite_body.merge('allowed_children' => 'feature')
    result = call(body)
    expect(result).to be_err
    type_errors = result.details[:errors].select { |e| e[:code] == 'type' }
    expect(type_errors).not_to be_empty
    expect(type_errors.first[:path]).to match(/allowed_children/)
  end

  it 'rejects items that fail minLength inside allowed_children (ac-1 follow-up)' do
    body = composite_body.merge('allowed_children' => [''])
    result = call(body)
    expect(result).to be_err
    codes = result.details[:errors].map { |e| e[:code] }
    expect(codes).to include('minLength')
  end

  it 'flags unknown_workflow for keys not in the registry (ac-2)' do
    Dir.mktmpdir('owl-validator-') do |dir|
      root = Pathname.new(dir)
      (root + '.owl').mkpath
      (root + '.owl' + 'workflows.yaml').write(<<~YAML)
        schema_version: 1
        workflows:
          feature:
            enabled: true
            source: workflows/feature/workflow.yaml
      YAML

      body = composite_body.merge('allowed_children' => ['foo'])
      result = call(body, root: root)
      expect(result).to be_err
      unknown = result.details[:errors].find { |e| e[:code] == 'unknown_workflow' }
      expect(unknown).not_to be_nil
      expect(unknown[:path]).to eq('/allowed_children/0')
      expect(unknown[:message]).to include("'foo'")
      expect(unknown[:message]).to include('registry')
    end
  end

  it 'flags allowed_children_on_non_composite for kind: task + non-empty list (ac-3)' do
    body = task_body.merge('allowed_children' => ['feature'])
    result = call(body)
    expect(result).to be_err
    err = result.details[:errors].find { |e| e[:code] == 'allowed_children_on_non_composite' }
    expect(err).not_to be_nil
    expect(err[:path]).to eq('/allowed_children')
    expect(err[:message]).to include('composite_task')
    expect(err[:message]).to include('kind: task')
  end

  it 'flags allowed_children_on_non_composite for kind: task + empty list (ac-3)' do
    body = task_body.merge('allowed_children' => [])
    result = call(body)
    expect(result).to be_err
    codes = result.details[:errors].map { |e| e[:code] }
    expect(codes).to include('allowed_children_on_non_composite')
  end

  it 'tolerates duplicate keys in allowed_children silently (ac-9)' do
    Dir.mktmpdir('owl-validator-') do |dir|
      root = Pathname.new(dir)
      (root + '.owl').mkpath
      (root + '.owl' + 'workflows.yaml').write(<<~YAML)
        schema_version: 1
        workflows:
          feature:
            enabled: true
            source: workflows/feature/workflow.yaml
      YAML

      body = composite_body.merge('allowed_children' => %w[feature feature])
      result = call(body, root: root)
      expect(result).to be_ok
    end
  end

  it 'accepts a composite body with a registered allowed_children list' do
    Dir.mktmpdir('owl-validator-') do |dir|
      root = Pathname.new(dir)
      (root + '.owl').mkpath
      (root + '.owl' + 'workflows.yaml').write(<<~YAML)
        schema_version: 1
        workflows:
          feature:
            enabled: true
            source: workflows/feature/workflow.yaml
      YAML

      body = composite_body.merge('allowed_children' => ['feature'])
      expect(call(body, root: root)).to be_ok
    end
  end

  it 'skips referential lookup when root is nil but field shape is valid' do
    body = composite_body.merge('allowed_children' => ['foo'])
    # no root => no registry => no unknown_workflow error; structurally valid
    expect(call(body, root: nil)).to be_ok
  end
end
