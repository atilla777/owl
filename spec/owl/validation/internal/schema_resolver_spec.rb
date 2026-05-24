# frozen_string_literal: true

require 'json'

require 'owl/validation/internal/schema_resolver'

RSpec.describe Owl::Validation::Internal::SchemaResolver do
  describe '.local_override' do
    it 'returns nil when RootDetector finds no .owl/ control plane' do
      with_tmp_project do |dir|
        result = described_class.local_override('workflow.json', cwd: dir.to_s)

        expect(result).to be_nil
      end
    end

    it 'returns nil when control plane exists but the schema file is absent' do
      with_tmp_project do |dir|
        FileUtils.mkdir_p((dir + '.owl').to_s)

        result = described_class.local_override('workflow.json', cwd: dir.to_s)

        expect(result).to be_nil
      end
    end

    it 'returns parsed JSON when .owl/schemas/<name> exists with valid JSON' do
      with_tmp_project do |dir|
        override = { '$id' => 'https://owl.dev/schemas/workflow/v1.json',
                     'title' => 'Local override' }
        write((dir + '.owl' + 'schemas' + 'workflow.json').to_s, JSON.generate(override))

        result = described_class.local_override('workflow.json', cwd: dir.to_s)

        expect(result).to eq(override)
      end
    end

    it 'raises RuntimeError with path and parser cause when override JSON is malformed' do
      with_tmp_project do |dir|
        path = write((dir + '.owl' + 'schemas' + 'workflow.json').to_s, '{ not json')

        expect {
          described_class.local_override('workflow.json', cwd: dir.to_s)
        }.to raise_error(RuntimeError, /invalid local override at #{Regexp.escape(path.to_s)}.*JSON::ParserError/)
      end
    end

    it 'raises RuntimeError with path when override file is empty (0 bytes)' do
      with_tmp_project do |dir|
        path = write((dir + '.owl' + 'schemas' + 'workflow.json').to_s, '')

        expect {
          described_class.local_override('workflow.json', cwd: dir.to_s)
        }.to raise_error(RuntimeError, /invalid local override at #{Regexp.escape(path.to_s)}.*JSON::ParserError/)
      end
    end

    it 'raises RuntimeError with path and SystemCallError cause when override file is unreadable' do
      skip 'root user bypasses chmod 000' if Process.uid.zero?

      with_tmp_project do |dir|
        path = write((dir + '.owl' + 'schemas' + 'workflow.json').to_s, '{}')
        File.chmod(0, path.to_s)
        begin
          expect {
            described_class.local_override('workflow.json', cwd: dir.to_s)
          }.to raise_error(RuntimeError, /invalid local override at #{Regexp.escape(path.to_s)}.*Errno::/)
        ensure
          File.chmod(0o600, path.to_s)
        end
      end
    end
  end
end
