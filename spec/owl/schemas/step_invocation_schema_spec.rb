# frozen_string_literal: true

require 'json'

RSpec.describe 'step_invocation JSON Schema' do
  let(:schema_path) { File.expand_path('../../../lib/owl/schemas/step_invocation.json', __dir__) }
  let(:schema)      { JSON.parse(File.read(schema_path)) }

  it 'exists at lib/owl/schemas/step_invocation.json' do
    expect(File).to exist(schema_path)
  end

  it 'declares the JSON Schema Draft 2020-12 dialect' do
    expect(schema['$schema']).to eq('https://json-schema.org/draft/2020-12/schema')
  end

  it 'requires the top-level keys produced by InvocationBuilder' do
    expect(schema['required']).to include('schema_version', 'task', 'step', 'inputs', 'outputs')
  end

  it 'declares task.kind as task | composite_task' do
    expect(schema.dig('properties', 'task', 'properties', 'kind', 'enum')).to eq(%w[task composite_task])
  end

  it 'declares step.status as the literal "ready" value' do
    expect(schema.dig('properties', 'step', 'properties', 'status', 'const')).to eq('ready')
  end

  it 'defines an artifact_descriptor as either resolved or unresolved' do
    one_of = schema.dig('$defs', 'artifact_descriptor', 'oneOf')
    refs = one_of.map { |entry| entry['$ref'] }
    expect(refs).to contain_exactly('#/$defs/artifact_resolved', '#/$defs/artifact_unresolved')
  end
end
