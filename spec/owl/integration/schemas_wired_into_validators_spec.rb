# frozen_string_literal: true

require 'owl/workflows/internal/workflow_validator'
require 'owl/artifacts/internal/artifact_type_validator'
require 'owl/validation/internal/schema_check'

RSpec.describe 'JSON schemas wired into runtime validators' do
  describe Owl::Workflows::Internal::WorkflowValidator do
    it 'loads schemas/workflow.json into the shared SchemaCheck registry' do
      schema = Owl::Validation::Internal::SchemaCheck.schema('workflow.json')
      expect(schema['$id']).to eq('https://owl.dev/schemas/workflow/v1.json')
    end

    it 'rejects a workflow body with kind outside the schema enum and surfaces a schema path' do
      body = { 'id' => 'broken', 'kind' => 'invalid', 'steps' => [] }
      result = described_class.validate(root: nil, body: body)

      expect(result).to be_a(Owl::Result::Err)
      expect(result.code).to eq(:workflow_validation_failed)

      schema_hit = result.details[:errors].find do |entry|
        entry[:path] == '$.kind' && entry[:code] == 'enum'
      end
      expect(schema_hit).not_to be_nil
      expect(schema_hit[:message]).to include('"invalid"')
    end

    it 'rejects a workflow step body that has both `context` and `context_file` via the schema `not` rule' do
      body = {
        'id' => 'broken',
        'kind' => 'task',
        'steps' => [
          { 'id' => 'step', 'context' => 'inline', 'context_file' => 'inline.md' }
        ]
      }
      result = described_class.validate(root: nil, body: body)

      expect(result).to be_a(Owl::Result::Err)
      messages = result.details[:errors].map { |e| e[:message] }
      schema_hit = messages.any? { |m| m.include?('context') && m.include?('context_file') }
      expect(schema_hit).to be(true)
    end
  end

  describe Owl::Artifacts::Internal::ArtifactTypeValidator do
    it 'loads schemas/artifact.json into the shared SchemaCheck registry' do
      schema = Owl::Validation::Internal::SchemaCheck.schema('artifact.json')
      expect(schema['$id']).to eq('https://owl.dev/schemas/artifact/v1.json')
    end

    it 'rejects an artifact body missing the schema-required `id`/`title`/`kind`' do
      result = described_class.validate(body: {})

      expect(result).to be_a(Owl::Result::Err)
      expect(result.code).to eq(:artifact_type_validation_failed)

      paths = result.details[:errors].map { |e| e[:path] }
      expect(paths).to include('$.id')
      expect(paths).to include('$.title')
      expect(paths).to include('$.kind')
    end

    it 'rejects front_matter.type outside the schema enum' do
      body = { 'id' => 'foo', 'title' => 'Foo', 'kind' => 'markdown',
               'front_matter' => { 'type' => 'tuple' } }
      result = described_class.validate(body: body)

      expect(result).to be_a(Owl::Result::Err)
      schema_hit = result.details[:errors].find do |entry|
        entry[:path] == '$.front_matter.type'
      end
      expect(schema_hit).not_to be_nil
      expect(schema_hit[:message]).to include('"tuple"')
    end
  end
end
