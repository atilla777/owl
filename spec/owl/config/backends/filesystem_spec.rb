# frozen_string_literal: true

require 'owl/config/backends/filesystem'

RSpec.describe Owl::Config::Backends::Filesystem do
  def valid_body(project_id: 'sample')
    Owl::Config::Backends::Filesystem.new(root: nil).default_template(project_id: project_id)
  end

  def build(root:)
    described_class.new(root: root)
  end

  describe '#load' do
    it 'returns Ok with a parsed Document for a valid config file' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_body(project_id: 'sample'))

        result = build(root: root).load
        expect(result).to be_ok

        document = result.value
        expect(document.schema_version).to eq(1)
        expect(document.project['id']).to eq('sample')
        expect(document.active_profile_name).to eq('default')
        expect(document.active_profile['backend']).to eq('filesystem')
      end
    end

    it 'returns Err(:config_missing) when .owl/config.yaml is absent' do
      with_tmp_project do |root|
        result = build(root: root).load
        expect(result).to be_err
        expect(result.code).to eq(:config_missing)
        expect(result.details[:path]).to end_with('.owl/config.yaml')
      end
    end

    it 'returns Err(:config_invalid_yaml) on a YAML syntax error' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", ": :\n  :\n")
        result = build(root: root).load
        expect(result).to be_err
        expect(result.code).to eq(:config_invalid_yaml)
      end
    end

    it 'returns Err(:config_invalid) when YAML root is not a mapping' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", "- one\n- two\n")
        result = build(root: root).load
        expect(result).to be_err
        expect(result.code).to eq(:config_invalid)
      end
    end
  end

  describe '#validate' do
    it 'returns Ok for a complete default config' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_body)
        expect(build(root: root).validate).to be_ok
      end
    end

    it 'returns Err(:config_validation_failed) for an incomplete schema' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", <<~YAML)
          schema_version: 1
          project:
            id: sample
        YAML
        result = build(root: root).validate
        expect(result).to be_err
        expect(result.code).to eq(:config_validation_failed)
        expect(result.details[:errors]).to be_a(Array)
        expect(result.details[:errors]).not_to be_empty
      end
    end
  end

  describe '#read_key' do
    it 'returns Ok with the value for a known key' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_body)
        result = build(root: root).read_key(key: 'settings.language.communication')
        expect(result).to be_ok
        expect(result.value).to eq(key: 'settings.language.communication', value: 'en')
      end
    end

    it 'reads non-settings paths now that the whitelist is removed' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_body)
        result = build(root: root).read_key(key: 'project.id')
        expect(result).to be_ok
        expect(result.value).to eq(key: 'project.id', value: 'sample')
      end
    end

    it 'returns Err(:invalid_config_key) for empty / malformed key' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_body)
        result = build(root: root).read_key(key: '')
        expect(result).to be_err
        expect(result.code).to eq(:invalid_config_key)
      end
    end

    it 'returns Err(:config_key_missing) for an unknown settings key' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_body)
        result = build(root: root).read_key(key: 'settings.does_not_exist')
        expect(result).to be_err
        expect(result.code).to eq(:config_key_missing)
      end
    end
  end

  describe '#write_key' do
    it 'persists a new value through atomic rename and returns Ok' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_body)
        backend = build(root: root)

        result = backend.write_key(key: 'settings.language.communication', value: 'ru')
        expect(result).to be_ok
        expect(result.value).to eq(key: 'settings.language.communication', value: 'ru')

        re_read = backend.read_key(key: 'settings.language.communication')
        expect(re_read.value[:value]).to eq('ru')
      end
    end

    it 'writes non-settings paths now that the whitelist is removed' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_body)
        backend = build(root: root)

        result = backend.write_key(key: 'workflow.feature.phases', value: '["plan","implement"]')
        expect(result).to be_ok
        expect(result.value).to eq(key: 'workflow.feature.phases', value: %w[plan implement])

        re_read = backend.read_key(key: 'workflow.feature.phases')
        expect(re_read.value[:value]).to eq(%w[plan implement])
      end
    end

    it 'returns Err(:invalid_config_value) for invalid JSON-shaped input' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_body)
        result = build(root: root).write_key(key: 'settings.language.communication', value: '{not json')
        expect(result).to be_err
        expect(result.code).to eq(:invalid_config_value)
      end
    end

    it 'returns Err(:config_validation_failed) when the resulting document is invalid' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_body)
        result = build(root: root).write_key(key: 'settings.storage.backend', value: 's3')
        expect(result).to be_err
        expect(result.code).to eq(:config_validation_failed)
      end
    end
  end

  describe '#snapshot' do
    it 'returns Ok with schema_version, project, settings, and storage' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_body)
        result = build(root: root).snapshot
        expect(result).to be_ok

        snap = result.value
        expect(snap[:schema_version]).to eq(1)
        expect(snap[:project]['id']).to eq('sample')
        expect(snap[:storage][:active_profile]).to eq('default')
        expect(snap[:storage][:roles_present]).to include('control', 'tasks', 'docs')
      end
    end

    it 'returns Err(:config_missing) when config is absent' do
      with_tmp_project do |root|
        result = build(root: root).snapshot
        expect(result).to be_err
        expect(result.code).to eq(:config_missing)
      end
    end
  end

  describe '#default_template' do
    it 'renders the seeded template body for the given project_id' do
      body = described_class.new(root: nil).default_template(project_id: 'demo')
      expect(body).to include('id: demo')
      expect(body).to include('backend: filesystem')
    end

    it 'ignores the bound @root (Layer-C bootstrap exception)' do
      with_tmp_project do |root|
        body = build(root: root).default_template(project_id: 'demo')
        expect(body).not_to include(root.to_s)
      end
    end
  end
end
