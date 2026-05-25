# frozen_string_literal: true

require 'json'

require 'owl/internal/paths'

RSpec.describe 'workflow JSON Schema' do
  let(:schema_path) { File.join(Owl::Internal::Paths.schemas_dir, 'workflow.json') }
  let(:schema)      { JSON.parse(File.read(schema_path)) }

  it 'exists at schemas/workflow.json' do
    expect(File).to exist(schema_path)
  end

  it 'declares the JSON Schema Draft 2020-12 dialect' do
    expect(schema['$schema']).to eq('https://json-schema.org/draft/2020-12/schema')
  end

  it 'leaves the top-level workflow body extensible (additionalProperties: true)' do
    expect(schema['additionalProperties']).to be(true)
  end

  it 'declares publishes as an array of publish_rule items' do
    publishes = schema.dig('properties', 'publishes')
    expect(publishes['type']).to eq('array')
    expect(publishes.dig('items', '$ref')).to eq('#/$defs/publish_rule')
  end

  it 'requires from and to inside publish_rule and forbids additional keys' do
    rule = schema.dig('$defs', 'publish_rule')
    expect(rule['required']).to contain_exactly('from', 'to')
    expect(rule['additionalProperties']).to be(false)
    expect(rule.dig('properties', 'from', 'minLength')).to eq(1)
    expect(rule.dig('properties', 'to', 'minLength')).to eq(1)
  end

  it 'declares step.context as a string property' do
    expect(schema.dig('$defs', 'step', 'properties', 'context', 'type')).to eq('string')
  end

  it 'declares step.context_file as a non-empty string property' do
    context_file = schema.dig('$defs', 'step', 'properties', 'context_file')
    expect(context_file['type']).to eq('string')
    expect(context_file['minLength']).to eq(1)
  end

  it 'forbids step.context and step.context_file together via not/required' do
    expect(schema.dig('$defs', 'step', 'not', 'required')).to eq(%w[context context_file])
  end

  it 'declares allowed_children as an array of non-empty string items' do
    prop = schema.dig('properties', 'allowed_children')
    expect(prop['type']).to eq('array')
    expect(prop.dig('items', 'type')).to eq('string')
    expect(prop.dig('items', 'minLength')).to eq(1)
  end

  it 'documents allowed_children semantics relative to composite_task kind' do
    prop = schema.dig('properties', 'allowed_children')
    expect(prop['description']).to include('composite_task')
  end
end
