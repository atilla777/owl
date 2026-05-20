# frozen_string_literal: true

require 'owl/artifacts/local'

RSpec.describe Owl::Artifacts::Local do
  describe Owl::Artifacts::Local::ArtifactType do
    it 'stores source_path and template_path as value attributes' do
      at = described_class.new(
        source_path: '/tmp/p/.owl/artifacts/brief/artifact.yaml',
        template_path: '/tmp/p/.owl/artifacts/brief/templates/default.md'
      )
      expect(at.source_path).to eq('/tmp/p/.owl/artifacts/brief/artifact.yaml')
      expect(at.template_path).to eq('/tmp/p/.owl/artifacts/brief/templates/default.md')
    end

    it 'allows nil template_path (validate flow has no template view yet)' do
      at = described_class.new(source_path: '/tmp/p/.owl/artifacts/x/artifact.yaml', template_path: nil)
      expect(at.template_path).to be_nil
    end
  end
end
