# frozen_string_literal: true

require 'owl/internal/cycle_detector'

RSpec.describe Owl::Internal::CycleDetector do
  describe '.detect' do
    it 'returns nil for an acyclic graph' do
      adjacency = { 'a' => ['b'], 'b' => ['c'], 'c' => [] }
      expect(described_class.detect(adjacency)).to be_nil
    end

    it 'returns the cycle path (first == last) for a direct cycle' do
      adjacency = { 'a' => ['b'], 'b' => ['a'] }
      cycle = described_class.detect(adjacency)
      expect(cycle.first).to eq(cycle.last)
      expect(cycle).to include('a', 'b')
    end

    it 'detects a transitive cycle' do
      adjacency = { 'a' => ['b'], 'b' => ['c'], 'c' => ['a'] }
      cycle = described_class.detect(adjacency)
      expect(cycle.first).to eq(cycle.last)
    end

    it 'tolerates neighbors that are not keys (dangling refs) without raising' do
      adjacency = { 'a' => ['ghost'] }
      expect(described_class.detect(adjacency)).to be_nil
    end

    it 'returns nil for an empty graph' do
      expect(described_class.detect({})).to be_nil
    end

    it 'detects a self-loop' do
      adjacency = { 'a' => ['a'] }
      cycle = described_class.detect(adjacency)
      expect(cycle).to eq(%w[a a])
    end
  end
end
