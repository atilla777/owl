# frozen_string_literal: true

require 'owl/tasks/internal/task_statuses'
require 'owl/tasks/internal/availability_scanner'
require 'owl/tasks/internal/ready_scanner'

RSpec.describe Owl::Tasks::Internal::TaskStatuses do
  it 'lists the three task-level terminal statuses' do
    expect(described_class::TERMINAL).to contain_exactly('archived', 'abandoned', 'done')
  end

  it 'is the single source the availability and ready scanners both reuse' do
    expect(Owl::Tasks::Internal::AvailabilityScanner::TERMINAL_STATUSES)
      .to be(described_class::TERMINAL)
    expect(Owl::Tasks::Internal::ReadyScanner::TERMINAL_STATUSES)
      .to be(described_class::TERMINAL)
  end

  it 'keeps the step-level completion-gate terminal set distinct' do
    require 'owl/tasks/internal/archive/completion_gate'
    expect(Owl::Tasks::Internal::Archive::CompletionGate::TERMINAL_STATUSES)
      .not_to eq(described_class::TERMINAL)
  end
end
