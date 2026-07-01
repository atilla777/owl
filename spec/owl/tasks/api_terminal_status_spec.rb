# frozen_string_literal: true

require 'owl/tasks/api'

RSpec.describe Owl::Tasks::Api, '.terminal_status?' do
  it 'is true for each TASK-level terminal status' do
    %w[archived abandoned done].each do |status|
      expect(described_class.terminal_status?(status)).to be(true)
    end
  end

  it 'is false for non-terminal statuses' do
    %w[open in_progress blocked on_hold].each do |status|
      expect(described_class.terminal_status?(status)).to be(false)
    end
  end

  it 'coerces non-string input via to_s' do
    expect(described_class.terminal_status?(:done)).to be(true)
    expect(described_class.terminal_status?(nil)).to be(false)
  end
end
