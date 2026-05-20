# frozen_string_literal: true

require 'tempfile'

require 'owl/cli/internal/user_file_reader'

RSpec.describe Owl::Cli::Internal::UserFileReader do
  describe '.read' do
    it 'returns Result.ok with file contents when the path exists' do
      Tempfile.create(['brief', '.md']) do |f|
        f.write("hello\n")
        f.flush
        result = described_class.read(path: f.path)
        expect(result).to be_ok
        expect(result.value).to eq("hello\n")
      end
    end

    it 'returns Result.err :user_file_missing when the path does not exist' do
      result = described_class.read(path: '/tmp/owl-user-file-reader-missing-xyz')
      expect(result).to be_err
      expect(result.code).to eq(:user_file_missing)
      expect(result.details[:path]).to eq('/tmp/owl-user-file-reader-missing-xyz')
    end

    it 'coerces non-string path values via to_s' do
      Tempfile.create(['brief', '.md']) do |f|
        f.write('x')
        f.flush
        result = described_class.read(path: Pathname.new(f.path))
        expect(result).to be_ok
        expect(result.value).to eq('x')
      end
    end
  end
end
