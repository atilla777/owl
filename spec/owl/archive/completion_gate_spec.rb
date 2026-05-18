# frozen_string_literal: true

require 'owl/tasks/internal/archive/completion_gate'

RSpec.describe Owl::Tasks::Internal::Archive::CompletionGate do
  def workflow_with(*step_ids)
    { 'steps' => step_ids.map { |id| { 'id' => id } } }
  end

  def task_with(steps)
    { 'steps' => steps.map { |id, status| { 'id' => id, 'status' => status } } }
  end

  describe '.call' do
    it 'returns ok when every step is done' do
      result = described_class.call(
        workflow_body: workflow_with('specify', 'verify', 'publish'),
        task_payload: task_with([%w[specify done], %w[verify done], %w[publish done]])
      )
      expect(result).to be_ok
    end

    it 'returns ok when steps are a mix of done and skipped' do
      result = described_class.call(
        workflow_body: workflow_with('specify', 'verify', 'publish'),
        task_payload: task_with([%w[specify done], %w[verify skipped], %w[publish done]])
      )
      expect(result).to be_ok
    end

    it 'flags running steps as workflow_incomplete' do
      result = described_class.call(
        workflow_body: workflow_with('specify', 'verify', 'publish'),
        task_payload: task_with([%w[specify done], %w[verify running], %w[publish pending]])
      )
      expect(result).to be_err
      expect(result.code).to eq(:workflow_incomplete)
      ids = result.details[:incomplete_steps].map { |s| s[:id] }
      expect(ids).to eq(%w[verify publish])
    end

    it 'flags failed steps as workflow_incomplete' do
      result = described_class.call(
        workflow_body: workflow_with('specify', 'publish'),
        task_payload: task_with([%w[specify failed], %w[publish done]])
      )
      expect(result).to be_err
      expect(result.code).to eq(:workflow_incomplete)
    end

    it 'requires publish to be done when present and not skipped (publish-only incomplete)' do
      result = described_class.call(
        workflow_body: workflow_with('specify', 'publish'),
        task_payload: task_with([%w[specify done], %w[publish pending]])
      )
      expect(result).to be_err
      # publish is the only incomplete step → publish_required is the more specific signal.
      expect(result.code).to eq(:publish_required)
    end

    it 'accepts a skipped publish step (opt-out)' do
      result = described_class.call(
        workflow_body: workflow_with('specify', 'publish'),
        task_payload: task_with([%w[specify done], %w[publish skipped]])
      )
      expect(result).to be_ok
    end

    it 'is ok when the workflow has no publish step at all' do
      result = described_class.call(
        workflow_body: workflow_with('specify', 'verify'),
        task_payload: task_with([%w[specify done], %w[verify done]])
      )
      expect(result).to be_ok
    end

    it 'returns publish_required when all non-publish steps are done but publish is pending' do
      # Order incomplete steps in graph order: ['publish'].
      result = described_class.call(
        workflow_body: workflow_with('specify', 'verify', 'publish'),
        task_payload: task_with([%w[specify done], %w[verify done], %w[publish pending]])
      )
      expect(result).to be_err
      # Only publish remains -> publish_required is the more specific signal.
      expect(result.code).to eq(:publish_required)
    end

    it 'orders incomplete_steps by workflow graph order, not task.yaml order' do
      result = described_class.call(
        workflow_body: workflow_with('a', 'b', 'c'),
        task_payload: { 'steps' => [
          { 'id' => 'c', 'status' => 'pending' },
          { 'id' => 'a', 'status' => 'pending' },
          { 'id' => 'b', 'status' => 'done' }
        ] }
      )
      expect(result).to be_err
      ids = result.details[:incomplete_steps].map { |s| s[:id] }
      expect(ids).to eq(%w[a c])
    end
  end
end
