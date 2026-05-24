# frozen_string_literal: true

require 'pathname'

require 'owl/workflows/backends/filesystem'

RSpec.describe 'seeded workflows pass validate including filesystem refs' do
  GEM_ROOT = Pathname.new(File.expand_path('../../..', __dir__))
  SEEDED_WORKFLOWS = %w[feature composite_feature].freeze

  SEEDED_WORKFLOWS.each do |name|
    it "validates workflows/#{name}/workflow.yaml end-to-end" do
      source_path = GEM_ROOT.join('workflows', name, 'workflow.yaml')
      expect(source_path).to exist

      backend = Owl::Workflows::Backends::Filesystem.new(root: nil)
      result = backend.validate(id_or_path: source_path.to_s)
      if result.err?
        raise "expected ok, got errors: #{result.details[:errors].inspect}"
      end

      expect(result).to be_ok
    end
  end
end
