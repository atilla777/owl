# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoverageGate do
  describe '.full_suite_run?' do
    let(:full_set) do
      [
        'spec/owl/a_spec.rb',
        'spec/owl/b_spec.rb',
        'spec/owl/internal/c_spec.rb'
      ]
    end

    it 'returns true when the executed files equal the full spec set (order-independent)' do
      executed = full_set.reverse
      expect(described_class.full_suite_run?(executed, full_set)).to be(true)
    end

    it 'returns true when paths differ only by relative/absolute form' do
      executed = full_set.map { |path| File.expand_path(path) }
      expect(described_class.full_suite_run?(executed, full_set)).to be(true)
    end

    it 'returns false when only a subset of files is executed' do
      executed = ['spec/owl/a_spec.rb']
      expect(described_class.full_suite_run?(executed, full_set)).to be(false)
    end

    it 'returns false when a single file is run (the common partial-run case)' do
      executed = ['spec/owl/b_spec.rb']
      expect(described_class.full_suite_run?(executed, full_set)).to be(false)
    end
  end
end
