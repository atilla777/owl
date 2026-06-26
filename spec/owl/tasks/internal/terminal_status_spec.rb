# frozen_string_literal: true

require 'owl/tasks/internal/terminal_status'

RSpec.describe Owl::Tasks::Internal::TerminalStatus do
  def payload(status:, steps:)
    { 'status' => status, 'steps' => steps }
  end

  def step(id, status)
    { 'id' => id, 'status' => status }
  end

  describe '.orchestration_terminal?' do
    it 'is false for a non-terminal status' do
      expect(described_class.orchestration_terminal?(payload(status: 'open', steps: [step('a', 'done')])))
        .to be(false)
    end

    it 'is true for an abandoned task regardless of remaining steps' do
      expect(described_class.orchestration_terminal?(payload(status: 'abandoned', steps: [step('a', 'ready')])))
        .to be(true)
    end

    it 'is false for an archived task still mid-flow (a step is not done)' do
      steps = [step('archive', 'done'), step('commit_push', 'pending')]
      expect(described_class.orchestration_terminal?(payload(status: 'archived', steps: steps))).to be(false)
    end

    it 'is true for an archived task whose every step is done or skipped' do
      steps = [step('archive', 'done'), step('commit_push', 'done'), step('opt', 'skipped')]
      expect(described_class.orchestration_terminal?(payload(status: 'archived', steps: steps))).to be(true)
    end

    it 'is true for a done task whose workflow is complete' do
      expect(described_class.orchestration_terminal?(payload(status: 'done', steps: [step('a', 'done')])))
        .to be(true)
    end

    it 'is false for a terminal task carrying no steps' do
      expect(described_class.orchestration_terminal?(payload(status: 'archived', steps: []))).to be(false)
    end

    it 'tolerates a nil payload' do
      expect(described_class.orchestration_terminal?(nil)).to be(false)
    end
  end
end
