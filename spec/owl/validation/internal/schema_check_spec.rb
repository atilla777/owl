# frozen_string_literal: true

require 'json'

require 'owl/validation/internal/schema_check'

RSpec.describe Owl::Validation::Internal::SchemaCheck do
  before { described_class.reset! }
  after  { described_class.reset! }

  describe '.schema' do
    context 'when there is no .owl/ control plane in any parent' do
      it 'returns the gem-bundled workflow.json' do
        with_tmp_project do |dir|
          Dir.chdir(dir.to_s) do
            schema = described_class.schema('workflow.json')

            expect(schema['$id']).to eq('https://owl.dev/schemas/workflow/v1.json')
          end
        end
      end

      it 'returns the gem-bundled artifact.json' do
        with_tmp_project do |dir|
          Dir.chdir(dir.to_s) do
            schema = described_class.schema('artifact.json')

            expect(schema['$id']).to eq('https://owl.dev/schemas/artifact/v1.json')
          end
        end
      end
    end

    context 'when .owl/ control plane exists without override files' do
      it 'falls back to gem-bundled for workflow.json' do
        with_tmp_project do |dir|
          FileUtils.mkdir_p((dir + '.owl').to_s)
          Dir.chdir(dir.to_s) do
            schema = described_class.schema('workflow.json')

            expect(schema['$id']).to eq('https://owl.dev/schemas/workflow/v1.json')
          end
        end
      end
    end

    context 'when .owl/schemas/workflow.json exists with valid JSON' do
      it 'returns the local override for workflow.json' do
        with_tmp_project do |dir|
          override = { '$id' => 'https://owl.dev/schemas/workflow/v1.json',
                       'title' => 'Local workflow override' }
          write((dir + '.owl' + 'schemas' + 'workflow.json').to_s, JSON.generate(override))

          Dir.chdir(dir.to_s) do
            expect(described_class.schema('workflow.json')).to eq(override)
          end
        end
      end

      it 'returns the local override for artifact.json without a separate code branch' do
        with_tmp_project do |dir|
          override = { '$id' => 'https://owl.dev/schemas/artifact/v1.json',
                       'title' => 'Local artifact override' }
          write((dir + '.owl' + 'schemas' + 'artifact.json').to_s, JSON.generate(override))

          Dir.chdir(dir.to_s) do
            expect(described_class.schema('artifact.json')).to eq(override)
          end
        end
      end
    end

    context 'cross-process actuality (simulated via reset!)' do
      it 'reads override in one logical process and gem-bundled in the next' do
        with_tmp_project do |dir_with|
          override = { '$id' => 'https://owl.dev/schemas/workflow/v1.json',
                       'title' => 'Override' }
          write((dir_with + '.owl' + 'schemas' + 'workflow.json').to_s, JSON.generate(override))
          Dir.chdir(dir_with.to_s) do
            expect(described_class.schema('workflow.json')).to eq(override)
          end
        end

        described_class.reset!

        with_tmp_project do |dir_without|
          Dir.chdir(dir_without.to_s) do
            schema = described_class.schema('workflow.json')

            expect(schema['$id']).to eq('https://owl.dev/schemas/workflow/v1.json')
            expect(schema['title']).not_to eq('Override')
          end
        end
      end
    end

    context 'when override file is malformed' do
      it 'raises RuntimeError with the override path for broken JSON' do
        with_tmp_project do |dir|
          path = write((dir + '.owl' + 'schemas' + 'workflow.json').to_s, '{ not json')

          Dir.chdir(dir.to_s) do
            expect do
              described_class.schema('workflow.json')
            end.to raise_error(RuntimeError, /invalid local override at #{Regexp.escape(path.to_s)}/)
          end
        end
      end

      it 'raises RuntimeError with the override path for an empty file' do
        with_tmp_project do |dir|
          path = write((dir + '.owl' + 'schemas' + 'workflow.json').to_s, '')

          Dir.chdir(dir.to_s) do
            expect do
              described_class.schema('workflow.json')
            end.to raise_error(RuntimeError, /invalid local override at #{Regexp.escape(path.to_s)}/)
          end
        end
      end

      it 'raises RuntimeError with the override path for an unreadable file' do
        skip 'root user bypasses chmod 000' if Process.uid.zero?

        with_tmp_project do |dir|
          path = write((dir + '.owl' + 'schemas' + 'workflow.json').to_s, '{}')
          File.chmod(0, path.to_s)
          begin
            Dir.chdir(dir.to_s) do
              expect do
                described_class.schema('workflow.json')
              end.to raise_error(RuntimeError, /invalid local override at #{Regexp.escape(path.to_s)}/)
            end
          ensure
            File.chmod(0o600, path.to_s)
          end
        end
      end
    end

    context 'in-process cache survives override removal' do
      it 'returns the originally cached override even after the file is gone' do
        with_tmp_project do |dir|
          override_path = write((dir + '.owl' + 'schemas' + 'workflow.json').to_s,
                                JSON.generate({ '$id' => 'https://owl.dev/schemas/workflow/v1.json',
                                                'title' => 'Cached override' }))

          Dir.chdir(dir.to_s) do
            first = described_class.schema('workflow.json')
            File.unlink(override_path.to_s)
            second = described_class.schema('workflow.json')

            expect(second).to equal(first)
            expect(second['title']).to eq('Cached override')
          end
        end
      end
    end
  end

  describe '.walk' do
    it 'validates via the override schema when it is present' do
      with_tmp_project do |dir|
        override = {
          '$id' => 'https://owl.dev/schemas/workflow/v1.json',
          'type' => 'object',
          'required' => ['marker'],
          'properties' => { 'marker' => { 'type' => 'string' } }
        }
        write((dir + '.owl' + 'schemas' + 'workflow.json').to_s, JSON.generate(override))

        Dir.chdir(dir.to_s) do
          errors = described_class.walk('workflow.json', {})

          expect(errors.map { |e| e[:path] }).to include('$.marker')
        end
      end
    end
  end
end
