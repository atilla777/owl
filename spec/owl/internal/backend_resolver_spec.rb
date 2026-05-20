# frozen_string_literal: true

require 'fileutils'

require 'owl/internal/backend_resolver'

RSpec.describe Owl::Internal::BackendResolver do
  shared_examples 'returns the matching filesystem backend' do |scope:, klass:|
    it "returns Result.ok wrapping Owl::#{klass.name.split('::')[1..2].join('::')}" do
      with_tmp_project do |root|
        result = described_class.resolve(root: root, scope: scope)
        expect(result).to be_a(Owl::Result::Ok)
        expect(result.value).to be_a(klass)
      end
    end
  end

  describe '.resolve' do
    it_behaves_like 'returns the matching filesystem backend',
                    scope: :tasks,
                    klass: Owl::Tasks::Backends::Filesystem
    it_behaves_like 'returns the matching filesystem backend',
                    scope: :workflows,
                    klass: Owl::Workflows::Backends::Filesystem
    it_behaves_like 'returns the matching filesystem backend',
                    scope: :storage,
                    klass: Owl::Storage::Backends::Filesystem
    it_behaves_like 'returns the matching filesystem backend',
                    scope: :config,
                    klass: Owl::Config::Backends::Filesystem

    it 'returns a storage filesystem backend when config explicitly selects "filesystem"' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", <<~YAML)
          settings:
            storage:
              backend: filesystem
        YAML
        result = described_class.resolve(root: root, scope: :storage)
        expect(result).to be_a(Owl::Result::Ok)
        expect(result.value).to be_a(Owl::Storage::Backends::Filesystem)
      end
    end

    it 'returns :unknown_backend for :storage scope when config picks an unrecognised name' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", <<~YAML)
          settings:
            storage:
              backend: imaginary
        YAML
        result = described_class.resolve(root: root, scope: :storage)
        expect(result).to be_a(Owl::Result::Err)
        expect(result.code).to eq(:unknown_backend)
        expect(result.message).to include('storage')
        expect(result.message).to include('imaginary')
        expect(result.details).to eq(scope: :storage, backend_name: 'imaginary')
      end
    end

    it 'treats explicit settings.storage.backend: "filesystem" as Filesystem' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", <<~YAML)
          settings:
            storage:
              backend: filesystem
        YAML
        result = described_class.resolve(root: root, scope: :tasks)
        expect(result).to be_a(Owl::Result::Ok)
        expect(result.value).to be_a(Owl::Tasks::Backends::Filesystem)
      end
    end

    it 'returns Result.err(:unknown_backend) for an unrecognised backend name' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", <<~YAML)
          settings:
            storage:
              backend: imaginary
        YAML
        result = described_class.resolve(root: root, scope: :tasks)
        expect(result).to be_a(Owl::Result::Err)
        expect(result.code).to eq(:unknown_backend)
        expect(result.message).to include('tasks')
        expect(result.message).to include('imaginary')
        expect(result.details).to eq(scope: :tasks, backend_name: 'imaginary')
      end
    end

    it 'mentions the scope in the unknown_backend message' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", <<~YAML)
          settings:
            storage:
              backend: imaginary
        YAML
        result = described_class.resolve(root: root, scope: :workflows)
        expect(result.code).to eq(:unknown_backend)
        expect(result.message).to include('workflows')
        expect(result.details[:scope]).to eq(:workflows)
      end
    end

    it 'falls back to Filesystem when .owl/config.yaml is missing' do
      with_tmp_project do |root|
        result = described_class.resolve(root: root, scope: :tasks)
        expect(result).to be_a(Owl::Result::Ok)
        expect(result.value).to be_a(Owl::Tasks::Backends::Filesystem)
      end
    end

    it 'falls back to Filesystem when settings.storage.backend is empty' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", <<~YAML)
          settings:
            storage:
              backend: ""
        YAML
        result = described_class.resolve(root: root, scope: :tasks)
        expect(result).to be_a(Owl::Result::Ok)
        expect(result.value).to be_a(Owl::Tasks::Backends::Filesystem)
      end
    end

    it 'falls back to Filesystem when config.yaml has invalid YAML' do
      with_tmp_project do |root|
        FileUtils.mkdir_p("#{root}/.owl")
        write("#{root}/.owl/config.yaml", ":\n  : broken")
        result = described_class.resolve(root: root, scope: :tasks)
        expect(result).to be_a(Owl::Result::Ok)
        expect(result.value).to be_a(Owl::Tasks::Backends::Filesystem)
      end
    end

    it 'falls back to Filesystem when YAML root is not a mapping' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", "- one\n- two\n")
        result = described_class.resolve(root: root, scope: :tasks)
        expect(result).to be_a(Owl::Result::Ok)
        expect(result.value).to be_a(Owl::Tasks::Backends::Filesystem)
      end
    end

    it 'falls back to Filesystem when settings.storage is not a mapping' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", <<~YAML)
          settings:
            storage: "literal"
        YAML
        result = described_class.resolve(root: root, scope: :tasks)
        expect(result).to be_a(Owl::Result::Ok)
        expect(result.value).to be_a(Owl::Tasks::Backends::Filesystem)
      end
    end

    it 'raises ArgumentError on an unknown scope' do
      with_tmp_project do |root|
        expect { described_class.resolve(root: root, scope: :artifacts) }
          .to raise_error(ArgumentError, /scope/)
      end
    end

    # Layer-C bootstrap exception #2 (see BackendResolver module header):
    # config domain is the bootstrap, so :config scope is always Filesystem.
    it 'returns Filesystem for :config scope even when settings.storage.backend is unknown' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", <<~YAML)
          settings:
            storage:
              backend: imaginary
        YAML
        result = described_class.resolve(root: root, scope: :config)
        expect(result).to be_a(Owl::Result::Ok)
        expect(result.value).to be_a(Owl::Config::Backends::Filesystem)
      end
    end

    # Bootstrap re-entrancy regression: BackendResolver.read_backend_name must
    # NOT route through Owl::Config::Api — that would create the cycle "selecting
    # the backend depends on Config::Api, which depends on the backend".
    it 'does not invoke Owl::Config::Api when reading the backend name' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", <<~YAML)
          settings:
            storage:
              backend: filesystem
        YAML

        allow(Owl::Config::Api).to receive(:load).and_raise('Config::Api must not be called by BackendResolver')
        allow(Owl::Config::Api).to receive(:validate).and_raise('Config::Api must not be called by BackendResolver')
        allow(Owl::Config::Api).to receive(:snapshot).and_raise('Config::Api must not be called by BackendResolver')
        allow(Owl::Config::Api).to receive(:read_key).and_raise('Config::Api must not be called by BackendResolver')

        result = described_class.resolve(root: root, scope: :storage)
        expect(result).to be_a(Owl::Result::Ok)
        expect(result.value).to be_a(Owl::Storage::Backends::Filesystem)
      end
    end
  end
end
