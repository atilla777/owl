# frozen_string_literal: true

require 'json'

require 'owl/internal/gem_assets'
require 'owl/internal/paths'

RSpec.describe Owl::Internal::GemAssets do
  describe '.read' do
    it 'reads a bundled schema file shipped with the gem' do
      contents = described_class.read('schemas/artifact.json')
      expect(contents).not_to be_empty
      expect { JSON.parse(contents) }.not_to raise_error
    end

    it 'raises Errno::ENOENT for missing assets' do
      expect { described_class.read('schemas/does-not-exist.json') }
        .to raise_error(Errno::ENOENT)
    end
  end
end
