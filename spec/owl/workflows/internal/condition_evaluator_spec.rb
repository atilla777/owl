# frozen_string_literal: true

require 'owl/workflows/internal/condition_evaluator'

RSpec.describe Owl::Workflows::Internal::ConditionEvaluator do
  describe '.evaluate invalid predicates (no artifact read needed)' do
    def evaluate(predicate)
      described_class.evaluate(root: nil, task_id: 'TASK-0001', predicate: predicate)
    end

    it 'rejects a non-mapping predicate' do
      result = evaluate('nope')
      expect(result).to be_err
      expect(result.code).to eq(:invalid_condition)
    end

    it 'rejects a blank artifact key' do
      result = evaluate('artifact' => '  ', 'matches' => 'x')
      expect(result).to be_err
      expect(result.code).to eq(:invalid_condition)
    end

    it 'rejects a predicate with both matches and not_matches' do
      result = evaluate('artifact' => 'brief', 'matches' => 'a', 'not_matches' => 'b')
      expect(result).to be_err
      expect(result.message).to match(/exactly one of/)
    end

    it 'rejects a predicate with neither operator (empty operator string counts as absent)' do
      result = evaluate('artifact' => 'brief', 'matches' => '')
      expect(result).to be_err
      expect(result.message).to match(/exactly one of/)
    end

    it 'rejects an uncompilable regex' do
      result = evaluate('artifact' => 'brief', 'matches' => '(')
      expect(result).to be_err
      expect(result.message).to match(/not a valid regex/)
    end

    it 'reads symbol-keyed predicates too' do
      result = evaluate(artifact: 'brief', matches: 'a', not_matches: 'b')
      expect(result).to be_err
      expect(result.message).to match(/exactly one of/)
    end

    it 'treats an unresolvable artifact (no project root) as met: false (safe default)' do
      result = evaluate('artifact' => 'brief', 'matches' => 'anything')
      expect(result).to be_ok
      expect(result.value[:met]).to be(false)
    end
  end
end
