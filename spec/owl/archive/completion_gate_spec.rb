# frozen_string_literal: true

require 'owl/tasks/internal/archive/completion_gate'

RSpec.describe Owl::Tasks::Internal::Archive::CompletionGate do
  def workflow_with(*step_ids)
    { 'steps' => step_ids.map { |id| { 'id' => id } } }
  end

  # Linear workflow where each step `requires` its predecessor — needed to
  # exercise the archive-step downstream exemption (which walks `requires`).
  def linear_workflow(*step_ids)
    {
      'steps' => step_ids.each_with_index.map do |id, index|
        step = { 'id' => id }
        step['requires'] = [step_ids[index - 1]] if index.positive?
        step
      end
    }
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

    context 'with an archive step (feature-style workflow)' do
      # Reproduces the reported deadlock: the `archive` step is the step that
      # runs `owl archive`, so it is `running` at archive time, and the
      # post-archive `commit_push` step is still `pending`. Neither should
      # block the archive side effect.
      it 'allows archival while archive is running and commit_push is pending' do
        result = described_class.call(
          workflow_body: linear_workflow('implement', 'review_code', 'merge_docs', 'archive', 'commit_push'),
          task_payload: task_with([
                                    %w[implement done], %w[review_code done], %w[merge_docs done],
                                    %w[archive running], %w[commit_push pending]
                                  ])
        )
        expect(result).to be_ok
      end

      it 'allows archival even when the archive step has not been started yet' do
        result = described_class.call(
          workflow_body: linear_workflow('merge_docs', 'archive', 'commit_push'),
          task_payload: task_with([%w[merge_docs done], %w[archive pending], %w[commit_push pending]])
        )
        expect(result).to be_ok
      end

      it 'still blocks archival when a pre-archive step is not done' do
        result = described_class.call(
          workflow_body: linear_workflow('implement', 'review_code', 'merge_docs', 'archive', 'commit_push'),
          task_payload: task_with([
                                    %w[implement done], %w[review_code done], %w[merge_docs running],
                                    %w[archive running], %w[commit_push pending]
                                  ])
        )
        expect(result).to be_err
        expect(result.code).to eq(:workflow_incomplete)
        ids = result.details[:incomplete_steps].map { |s| s[:id] }
        expect(ids).to eq(%w[merge_docs])
      end

      it 'exempts the whole downstream closure of archive, not just the next step' do
        result = described_class.call(
          workflow_body: linear_workflow('merge_docs', 'archive', 'commit_push', 'notify'),
          task_payload: task_with([
                                    %w[merge_docs done], %w[archive running],
                                    %w[commit_push pending], %w[notify pending]
                                  ])
        )
        expect(result).to be_ok
      end

      it 'still requires a publish step that precedes archive' do
        result = described_class.call(
          workflow_body: linear_workflow('implement', 'publish', 'archive', 'commit_push'),
          task_payload: task_with([
                                    %w[implement done], %w[publish pending],
                                    %w[archive running], %w[commit_push pending]
                                  ])
        )
        expect(result).to be_err
        expect(result.code).to eq(:publish_required)
      end
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
