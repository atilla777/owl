# frozen_string_literal: true

require 'owl/workflows/internal/graph_builder'
require 'owl/workflows/internal/ready_resolver'

RSpec.describe Owl::Workflows::Internal::ReadyResolver do
  def graph_of(*ids_with_requires)
    steps = ids_with_requires.map do |entry|
      id, requires = entry
      { 'id' => id, 'kind' => 'noop', 'requires' => requires || [] }
    end
    Owl::Workflows::Internal::GraphBuilder.build(steps).value
  end

  describe '.resolve' do
    it 'returns initial steps with no requires when all are pending' do
      graph = graph_of(['a'], ['b', ['a']])
      task_steps = [
        { 'id' => 'a', 'status' => 'pending' },
        { 'id' => 'b', 'status' => 'pending' }
      ]
      ready = described_class.resolve(graph: graph, task_steps: task_steps)
      expect(ready.map { |s| s[:id] }).to eq(['a'])
      expect(ready.first[:status]).to eq('ready')
    end

    it 'unblocks downstream after the parent reaches done' do
      graph = graph_of(['a'], ['b', ['a']])
      task_steps = [
        { 'id' => 'a', 'status' => 'done' },
        { 'id' => 'b', 'status' => 'pending' }
      ]
      ready = described_class.resolve(graph: graph, task_steps: task_steps)
      expect(ready.map { |s| s[:id] }).to eq(['b'])
    end

    it 'treats skipped as unblocking (default for Owl)' do
      graph = graph_of(['a'], ['b', ['a']])
      task_steps = [
        { 'id' => 'a', 'status' => 'skipped' },
        { 'id' => 'b', 'status' => 'pending' }
      ]
      ready = described_class.resolve(graph: graph, task_steps: task_steps)
      expect(ready.map { |s| s[:id] }).to eq(['b'])
    end

    it 'keeps downstream blocked while parent is running' do
      graph = graph_of(['a'], ['b', ['a']])
      task_steps = [
        { 'id' => 'a', 'status' => 'running' },
        { 'id' => 'b', 'status' => 'pending' }
      ]
      ready = described_class.resolve(graph: graph, task_steps: task_steps)
      expect(ready).to be_empty
    end

    it 'omits steps that are already running, done, skipped, blocked, or failed' do
      graph = graph_of(['a'], ['b'])
      task_steps = [
        { 'id' => 'a', 'status' => 'running' },
        { 'id' => 'b', 'status' => 'done' }
      ]
      ready = described_class.resolve(graph: graph, task_steps: task_steps)
      expect(ready).to be_empty
    end

    it 'fan-in: c is ready only when both parents complete' do
      graph = graph_of(['a'], ['b'], ['c', %w[a b]])
      partial = [
        { 'id' => 'a', 'status' => 'done' },
        { 'id' => 'b', 'status' => 'pending' },
        { 'id' => 'c', 'status' => 'pending' }
      ]
      expect(described_class.resolve(graph: graph, task_steps: partial).map { |s| s[:id] }).to eq(['b'])

      both = [
        { 'id' => 'a', 'status' => 'done' },
        { 'id' => 'b', 'status' => 'skipped' },
        { 'id' => 'c', 'status' => 'pending' }
      ]
      expect(described_class.resolve(graph: graph, task_steps: both).map { |s| s[:id] }).to eq(['c'])
    end

    it 'treats missing status as pending' do
      graph = graph_of(['a'])
      task_steps = [{ 'id' => 'a' }]
      ready = described_class.resolve(graph: graph, task_steps: task_steps)
      expect(ready.map { |s| s[:id] }).to eq(['a'])
    end
  end
end
