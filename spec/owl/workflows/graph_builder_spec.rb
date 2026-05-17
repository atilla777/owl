# frozen_string_literal: true

require 'owl/workflows/internal/graph_builder'

RSpec.describe Owl::Workflows::Internal::GraphBuilder do
  describe '.build' do
    it 'builds a linear graph with topological order' do
      steps = [
        { 'id' => 'a' },
        { 'id' => 'b', 'requires' => ['a'] },
        { 'id' => 'c', 'requires' => ['b'] }
      ]
      result = described_class.build(steps)
      expect(result).to be_ok
      expect(result.value[:order]).to eq(%w[a b c])
      expect(result.value[:nodes]['b'][:requires]).to eq(['a'])
    end

    it 'supports fan-out: one parent, multiple children' do
      steps = [
        { 'id' => 'a' },
        { 'id' => 'b', 'requires' => ['a'] },
        { 'id' => 'c', 'requires' => ['a'] }
      ]
      result = described_class.build(steps)
      expect(result).to be_ok
      expect(result.value[:nodes]['b'][:requires]).to eq(['a'])
      expect(result.value[:nodes]['c'][:requires]).to eq(['a'])
    end

    it 'supports fan-in: multiple parents, one child' do
      steps = [
        { 'id' => 'a' },
        { 'id' => 'b' },
        { 'id' => 'c', 'requires' => %w[a b] }
      ]
      result = described_class.build(steps)
      expect(result).to be_ok
      expect(result.value[:nodes]['c'][:requires]).to eq(%w[a b])
    end

    it 'returns :workflow_cycle with the cycle path' do
      steps = [
        { 'id' => 'a', 'requires' => ['c'] },
        { 'id' => 'b', 'requires' => ['a'] },
        { 'id' => 'c', 'requires' => ['b'] }
      ]
      result = described_class.build(steps)
      expect(result).to be_err
      expect(result.code).to eq(:workflow_cycle)
      expect(result.details[:cycle].first).to eq(result.details[:cycle].last)
    end

    it 'returns :duplicate_step_id when two steps share an id' do
      steps = [
        { 'id' => 'a' },
        { 'id' => 'a' }
      ]
      result = described_class.build(steps)
      expect(result).to be_err
      expect(result.code).to eq(:duplicate_step_id)
      expect(result.details[:id]).to eq('a')
    end

    it 'returns :unknown_step_required when requires points to a missing id' do
      steps = [
        { 'id' => 'a', 'requires' => ['ghost'] }
      ]
      result = described_class.build(steps)
      expect(result).to be_err
      expect(result.code).to eq(:unknown_step_required)
      expect(result.details[:unknown]).to eq('ghost')
    end

    it 'returns :invalid_step_id when a step lacks an id' do
      steps = [
        { 'kind' => 'noop' }
      ]
      result = described_class.build(steps)
      expect(result).to be_err
      expect(result.code).to eq(:invalid_step_id)
    end

    it 'accepts symbol keys and coerces id to string' do
      steps = [{ id: :alpha }, { id: :beta, requires: [:alpha] }]
      result = described_class.build(steps)
      expect(result).to be_ok
      expect(result.value[:order]).to eq(%w[alpha beta])
    end

    it 'returns an empty graph for nil steps' do
      result = described_class.build(nil)
      expect(result).to be_ok
      expect(result.value[:order]).to eq([])
      expect(result.value[:nodes]).to eq({})
    end
  end
end
