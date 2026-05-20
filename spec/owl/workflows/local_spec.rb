# frozen_string_literal: true

require 'owl/workflows/local'

RSpec.describe Owl::Workflows::Local do
  describe Owl::Workflows::Local::WorkflowFile do
    it 'stores source_path as a value attribute' do
      wf = described_class.new(source_path: '/tmp/p/.owl/workflows/feature/workflow.yaml')
      expect(wf.source_path).to eq('/tmp/p/.owl/workflows/feature/workflow.yaml')
      expect(wf).to eq(described_class.new(source_path: '/tmp/p/.owl/workflows/feature/workflow.yaml'))
    end
  end
end
