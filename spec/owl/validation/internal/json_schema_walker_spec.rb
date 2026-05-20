# frozen_string_literal: true

require 'owl/validation/internal/json_schema_walker'

RSpec.describe Owl::Validation::Internal::JsonSchemaWalker do
  def errors_for(schema, instance)
    described_class.validate(schema, instance)
  end

  describe '.validate type' do
    it 'accepts a matching type' do
      expect(errors_for({ 'type' => 'string' }, 'hi')).to be_empty
    end

    it 'rejects a mismatched type with path + message' do
      errors = errors_for({ 'type' => 'string' }, 42)
      expect(errors.size).to eq(1)
      expect(errors.first[:keyword]).to eq('type')
      expect(errors.first[:path]).to eq('$')
      expect(errors.first[:message]).to include('expected type "string"')
    end

    it 'supports type as array (union)' do
      schema = { 'type' => %w[string null] }
      expect(errors_for(schema, 'x')).to be_empty
      expect(errors_for(schema, nil)).to be_empty
      expect(errors_for(schema, 7)).not_to be_empty
    end
  end

  describe '.validate required' do
    it 'reports missing required property' do
      schema = { 'type' => 'object', 'required' => %w[id] }
      errors = errors_for(schema, {})
      expect(errors.size).to eq(1)
      expect(errors.first[:keyword]).to eq('required')
      expect(errors.first[:path]).to eq('$.id')
      expect(errors.first[:message]).to include('missing required property `id`')
    end

    it 'passes when required property is present' do
      schema = { 'type' => 'object', 'required' => %w[id] }
      expect(errors_for(schema, { 'id' => 'x' })).to be_empty
    end
  end

  describe '.validate enum' do
    it 'rejects values outside enum' do
      errors = errors_for({ 'enum' => %w[task composite_task] }, 'bogus')
      expect(errors.size).to eq(1)
      expect(errors.first[:keyword]).to eq('enum')
    end

    it 'accepts values inside enum' do
      expect(errors_for({ 'enum' => %w[a b] }, 'a')).to be_empty
    end
  end

  describe '.validate const' do
    it 'accepts equal const' do
      expect(errors_for({ 'const' => 1 }, 1)).to be_empty
    end

    it 'rejects different const' do
      errors = errors_for({ 'const' => 1 }, 2)
      expect(errors.size).to eq(1)
      expect(errors.first[:keyword]).to eq('const')
    end
  end

  describe '.validate properties + additionalProperties' do
    it 'descends into declared properties' do
      schema = {
        'type' => 'object',
        'properties' => { 'name' => { 'type' => 'string' } }
      }
      errors = errors_for(schema, { 'name' => 7 })
      expect(errors.size).to eq(1)
      expect(errors.first[:path]).to eq('$.name')
      expect(errors.first[:keyword]).to eq('type')
    end

    it 'rejects extra keys when additionalProperties is false' do
      schema = {
        'type' => 'object',
        'properties' => { 'name' => { 'type' => 'string' } },
        'additionalProperties' => false
      }
      errors = errors_for(schema, { 'name' => 'x', 'extra' => 1 })
      expect(errors.map { |e| e[:keyword] }).to include('additionalProperties')
      expect(errors.find { |e| e[:keyword] == 'additionalProperties' }[:path]).to eq('$.extra')
    end

    it 'allows extra keys when additionalProperties is true (default)' do
      schema = {
        'type' => 'object',
        'properties' => { 'name' => { 'type' => 'string' } }
      }
      expect(errors_for(schema, { 'name' => 'x', 'whatever' => 1 })).to be_empty
    end
  end

  describe '.validate items' do
    it 'descends into array items' do
      schema = { 'type' => 'array', 'items' => { 'type' => 'string' } }
      errors = errors_for(schema, %w[a] + [1])
      expect(errors.size).to eq(1)
      expect(errors.first[:path]).to eq('$[1]')
    end
  end

  describe '.validate minLength' do
    it 'rejects shorter strings' do
      errors = errors_for({ 'type' => 'string', 'minLength' => 3 }, 'ab')
      expect(errors.size).to eq(1)
      expect(errors.first[:keyword]).to eq('minLength')
    end
  end

  describe '.validate minProperties' do
    it 'rejects too-empty objects' do
      errors = errors_for({ 'type' => 'object', 'minProperties' => 1 }, {})
      expect(errors.size).to eq(1)
      expect(errors.first[:keyword]).to eq('minProperties')
    end
  end

  describe '.validate pattern' do
    it 'rejects non-matching strings' do
      schema = { 'type' => 'string', 'pattern' => '^owl-step-[a-z_]+$' }
      errors = errors_for(schema, 'WRONG')
      expect(errors.size).to eq(1)
      expect(errors.first[:keyword]).to eq('pattern')
    end

    it 'accepts matching strings' do
      schema = { 'type' => 'string', 'pattern' => '^owl-step-[a-z_]+$' }
      expect(errors_for(schema, 'owl-step-run')).to be_empty
    end
  end

  describe '.validate not + required (mutually exclusive)' do
    it 'rejects an object that has all forbidden keys' do
      schema = {
        'type' => 'object',
        'not' => { 'required' => %w[context context_file] }
      }
      errors = errors_for(schema, { 'context' => 'a', 'context_file' => 'b' })
      expect(errors.size).to eq(1)
      expect(errors.first[:keyword]).to eq('not')
      expect(errors.first[:message]).to include('context')
      expect(errors.first[:message]).to include('context_file')
    end

    it 'accepts an object that has only one of the forbidden keys' do
      schema = {
        'type' => 'object',
        'not' => { 'required' => %w[context context_file] }
      }
      expect(errors_for(schema, { 'context' => 'a' })).to be_empty
    end
  end

  describe '.validate $ref to $defs' do
    it 'resolves local refs' do
      schema = {
        'type' => 'object',
        'properties' => { 'item' => { '$ref' => '#/$defs/Foo' } },
        '$defs' => { 'Foo' => { 'type' => 'string' } }
      }
      errors = errors_for(schema, { 'item' => 7 })
      expect(errors.size).to eq(1)
      expect(errors.first[:path]).to eq('$.item')
    end
  end
end
