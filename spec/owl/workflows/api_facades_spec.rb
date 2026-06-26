# frozen_string_literal: true

require 'owl/workflows/api'
require 'owl/workflows/internal/step_context_frontmatter_check'

# Coverage for the cli-adapter reader that exposes the
# StepContextFrontmatterCheck::CHECK_KEY sentinel (TASK-0040 WS3) so cli error
# classification need not reach into Workflows::Internal directly.
RSpec.describe Owl::Workflows::Api do
  describe '.step_context_frontmatter_check_key' do
    it 'returns the StepContextFrontmatterCheck CHECK_KEY sentinel' do
      expect(described_class.step_context_frontmatter_check_key)
        .to eq(Owl::Workflows::Internal::StepContextFrontmatterCheck::CHECK_KEY)
      expect(described_class.step_context_frontmatter_check_key).to eq(:step_context_frontmatter)
    end
  end
end
