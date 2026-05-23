# frozen_string_literal: true

require 'digest'

require 'owl/steps/internal/artifact_hasher'

RSpec.describe Owl::Steps::Internal::ArtifactHasher do
  describe '.call' do
    it 'returns the hex sha256 of the file contents' do
      with_tmp_project do |root|
        path = write("#{root}/artifact.md", "hello world\n")
        result = described_class.call(path: path)
        expect(result).to be_ok
        expect(result.value).to eq(Digest::SHA256.hexdigest("hello world\n"))
      end
    end

    it 'returns :artifact_missing when the file does not exist' do
      with_tmp_project do |root|
        result = described_class.call(path: "#{root}/missing.md")
        expect(result).to be_err
        expect(result.code).to eq(:artifact_missing)
        expect(result.details[:path]).to include('missing.md')
      end
    end

    it 'differs when contents differ' do
      with_tmp_project do |root|
        a = write("#{root}/a.md", 'a')
        b = write("#{root}/b.md", 'b')
        expect(described_class.call(path: a).value).not_to eq(described_class.call(path: b).value)
      end
    end
  end
end
