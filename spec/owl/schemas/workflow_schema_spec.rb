# frozen_string_literal: true

require 'json'

RSpec.describe 'workflow JSON Schema' do
  let(:schema_path) { File.expand_path('../../../lib/owl/schemas/workflow.json', __dir__) }
  let(:schema)      { JSON.parse(File.read(schema_path)) }

  it 'exists at lib/owl/schemas/workflow.json' do
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
end
