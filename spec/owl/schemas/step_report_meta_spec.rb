# frozen_string_literal: true

require 'json'

# Meta-spec for schemas/step_report.json — the public step-report contract
# (RFC #1 §4.3, §5). Catches drift between the published schema and the
# constants the runtime relies on.
RSpec.describe 'schemas/step_report.json (RFC #1 §4.3)' do
  let(:schema_path) { File.expand_path('../../../schemas/step_report.json', __dir__) }
  let(:schema) { JSON.parse(File.read(schema_path)) }

  it 'exists on disk' do
    expect(File).to exist(schema_path)
  end

  it 'is valid JSON' do
    expect { JSON.parse(File.read(schema_path)) }.not_to raise_error
  end

  it 'declares JSON Schema draft 2020-12' do
    expect(schema['$schema']).to eq('https://json-schema.org/draft/2020-12/schema')
  end

  it 'carries a stable $id versioned URL' do
    expect(schema['$id']).to eq('https://owl.dev/schemas/step_report/v1.json')
  end

  it 'declares type=object with status and summary required' do
    expect(schema['type']).to eq('object')
    expect(schema['required']).to eq(%w[status summary])
  end

  it 'lists the canonical status enum (RFC #1 §4.2 final_state space)' do
    statuses = schema.dig('properties', 'status', 'enum')
    expect(statuses).to eq(%w[returned_normally do_not_use error interrupted budget_exceeded])
  end

  it 'declares session_type as an optional discussion|execution string' do
    session = schema.dig('properties', 'session_type')
    expect(session['type']).to eq('string')
    expect(session['enum']).to eq(%w[discussion execution])
  end

  it 'declares Result as the single required H2 section' do
    expect(schema['x-required-sections']).to eq(['Result'])
  end
end
