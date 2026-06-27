# frozen_string_literal: true

require 'owl/config/api'

RSpec.describe Owl::Config::Api do
  def valid_config
    Owl::Config::Api.default_template(project_id: 'sample')
  end

  describe '.load' do
    it 'returns Ok with a Document for a valid config' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_config)

        result = described_class.load(root: root)

        expect(result).to be_ok
        document = result.value
        expect(document.schema_version).to eq(1)
        expect(document.project['id']).to eq('sample')
        expect(document.active_profile_name).to eq('default')
        expect(document.active_profile['backend']).to eq('filesystem')
      end
    end

    it 'returns Err when the config file is missing' do
      with_tmp_project do |root|
        result = described_class.load(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:config_missing)
      end
    end

    it 'returns Err on a YAML syntax error' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", ": :\n  :")
        result = described_class.load(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:config_invalid_yaml)
      end
    end

    it 'returns Err when YAML root is not a mapping' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", "- 1\n- 2\n")
        result = described_class.load(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:config_invalid)
      end
    end
  end

  describe '.validate' do
    it 'returns Ok for a complete default config' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_config)
        result = described_class.validate(root: root)
        expect(result).to be_ok
      end
    end

    it 'reports missing roles' do
      with_tmp_project do |root|
        body = <<~YAML
          schema_version: 1
          project:
            id: sample
          storage:
            active_profile: default
            profiles:
              default:
                backend: filesystem
                roles:
                  control: { path: "/tmp/control" }
        YAML
        write("#{root}/.owl/config.yaml", body)

        result = described_class.validate(root: root)
        expect(result).to be_err
        codes = result.details[:errors].map { |e| e[:code] }
        expect(codes).to include(:missing_role)
      end
    end

    it 'reports unsupported schema_version' do
      with_tmp_project do |root|
        body = <<~YAML
          schema_version: 99
          project:
            id: sample
          storage:
            active_profile: default
            profiles:
              default:
                backend: filesystem
                roles:
                  control: { path: "/tmp" }
                  local_state: { path: "/tmp" }
                  index: { path: "/tmp" }
                  tasks: { path: "/tmp" }
                  archive: { path: "/tmp" }
                  docs: { path: "/tmp" }
        YAML
        write("#{root}/.owl/config.yaml", body)

        result = described_class.validate(root: root)
        expect(result).to be_err
        codes = result.details[:errors].map { |e| e[:code] }
        expect(codes).to include(:unsupported_schema_version)
      end
    end

    it 'reports missing project id and missing profile' do
      with_tmp_project do |root|
        body = <<~YAML
          schema_version: 1
          project: {}
          storage:
            active_profile: ghost
            profiles: {}
        YAML
        write("#{root}/.owl/config.yaml", body)

        result = described_class.validate(root: root)
        expect(result).to be_err
        codes = result.details[:errors].map { |e| e[:code] }
        expect(codes).to include(:missing_project_id, :missing_profile)
      end
    end

    it 'reports a role with no path string' do
      with_tmp_project do |root|
        body = <<~YAML
          schema_version: 1
          project:
            id: sample
          storage:
            active_profile: default
            profiles:
              default:
                backend: filesystem
                roles:
                  control: { path: "" }
                  local_state: { path: "/tmp" }
                  index: { path: "/tmp" }
                  tasks: { path: "/tmp" }
                  archive: { path: "/tmp" }
                  docs: { path: "/tmp" }
        YAML
        write("#{root}/.owl/config.yaml", body)

        result = described_class.validate(root: root)
        expect(result).to be_err
        codes = result.details[:errors].map { |e| e[:code] }
        expect(codes).to include(:invalid_role_definition)
      end
    end

    it 'propagates load errors as-is' do
      with_tmp_project do |root|
        result = described_class.validate(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:config_missing)
      end
    end

    it 'reports a missing active_profile name' do
      with_tmp_project do |root|
        body = <<~YAML
          schema_version: 1
          project:
            id: sample
          storage:
            profiles:
              default:
                backend: filesystem
                roles: {}
        YAML
        write("#{root}/.owl/config.yaml", body)

        result = described_class.validate(root: root)
        expect(result).to be_err
        codes = result.details[:errors].map { |e| e[:code] }
        expect(codes).to include(:missing_active_profile)
      end
    end
  end

  describe '.default_template' do
    it 'includes the project id in the rendered config' do
      template = described_class.default_template(project_id: 'demo')
      expect(template).to include('id: demo')
      expect(template).to include('schema_version: 1')
    end

    it 'renders a settings: block with language, storage and workflows defaults' do
      template = described_class.default_template(project_id: 'demo')
      expect(template).to include('settings:')
      expect(template).to include('communication: en')
      expect(template).to include('backend: filesystem')
      expect(template).to include('workflows:')
    end
  end

  describe '.validate (settings block)' do
    def base_config_without_settings
      <<~YAML
        schema_version: 1
        project:
          id: sample
        storage:
          active_profile: default
          profiles:
            default:
              backend: filesystem
              roles:
                control: { path: "/tmp" }
                local_state: { path: "/tmp" }
                index: { path: "/tmp" }
                tasks: { path: "/tmp" }
                archive: { path: "/tmp" }
                docs: { path: "/tmp" }
      YAML
    end

    it 'accepts a config without a settings: block (backwards compat)' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", base_config_without_settings)
        result = described_class.validate(root: root)
        expect(result).to be_ok
      end
    end

    it 'accepts a settings block with only required language.communication' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml",
              "#{base_config_without_settings}settings:\n  language:\n    communication: ru\n")
        result = described_class.validate(root: root)
        expect(result).to be_ok
      end
    end

    it 'reports missing settings.language.communication when language section is present' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", "#{base_config_without_settings}settings:\n  language:\n    artifacts: en\n")
        result = described_class.validate(root: root)
        expect(result).to be_err
        codes = result.details[:errors].map { |e| e[:code] }
        expect(codes).to include(:missing_settings_language_communication)
      end
    end

    it 'reports invalid optional language values (non-string or empty)' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml",
              "#{base_config_without_settings}settings:\n  language:\n    communication: en\n    artifacts: ''\n")
        result = described_class.validate(root: root)
        expect(result).to be_err
        codes = result.details[:errors].map { |e| e[:code] }
        expect(codes).to include(:invalid_settings_language_value)
      end
    end

    it 'reports unsupported storage backend' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml",
              "#{base_config_without_settings}settings:\n  language:\n    communication: en\n  " \
              "storage:\n    backend: s3\n")
        result = described_class.validate(root: root)
        expect(result).to be_err
        codes = result.details[:errors].map { |e| e[:code] }
        expect(codes).to include(:unsupported_settings_storage_backend)
      end
    end

    it 'reports invalid settings.storage.roles path' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml",
              "#{base_config_without_settings}settings:\n  language:\n    communication: en\n  " \
              "storage:\n    roles:\n      tasks: ''\n")
        result = described_class.validate(root: root)
        expect(result).to be_err
        codes = result.details[:errors].map { |e| e[:code] }
        expect(codes).to include(:invalid_settings_storage_role_path)
      end
    end

    it 'reports invalid settings shape (non-hash)' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", "#{base_config_without_settings}settings: scalar\n")
        result = described_class.validate(root: root)
        expect(result).to be_err
        codes = result.details[:errors].map { |e| e[:code] }
        expect(codes).to include(:invalid_settings_shape)
      end
    end

    it 'reports invalid settings.language shape (non-hash)' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", "#{base_config_without_settings}settings:\n  language: scalar\n")
        result = described_class.validate(root: root)
        expect(result).to be_err
        codes = result.details[:errors].map { |e| e[:code] }
        expect(codes).to include(:invalid_settings_language_shape)
      end
    end

    it 'reports invalid settings.storage shape (non-hash)' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", "#{base_config_without_settings}settings:\n  storage: scalar\n")
        result = described_class.validate(root: root)
        expect(result).to be_err
        codes = result.details[:errors].map { |e| e[:code] }
        expect(codes).to include(:invalid_settings_storage_shape)
      end
    end

    it 'reports invalid settings.storage.roles shape (non-hash)' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", "#{base_config_without_settings}settings:\n  storage:\n    roles: scalar\n")
        result = described_class.validate(root: root)
        expect(result).to be_err
        codes = result.details[:errors].map { |e| e[:code] }
        expect(codes).to include(:invalid_settings_storage_roles_shape)
      end
    end
  end

  describe '.read_key' do
    it 'returns the value at a settings.* dot-path' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_config)
        result = described_class.read_key(root: root, key: 'settings.language.communication')
        expect(result).to be_ok
        expect(result.value).to eq(key: 'settings.language.communication', value: 'en')
      end
    end

    it 'reads non-settings paths now that the whitelist is removed' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_config)
        result = described_class.read_key(root: root, key: 'project.id')
        expect(result).to be_ok
        expect(result.value).to eq(key: 'project.id', value: 'sample')
      end
    end

    it 'reports missing key' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_config)
        result = described_class.read_key(root: root, key: 'settings.language.bogus')
        expect(result).to be_err
        expect(result.code).to eq(:config_key_missing)
      end
    end

    it 'reports invalid key shape' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_config)
        result = described_class.read_key(root: root, key: 'settings..language')
        expect(result).to be_err
        expect(result.code).to eq(:invalid_config_key)
      end
    end

    it 'propagates load errors as-is' do
      with_tmp_project do |root|
        result = described_class.read_key(root: root, key: 'settings.language.communication')
        expect(result).to be_err
        expect(result.code).to eq(:config_missing)
      end
    end

    it "resolves the 'version' read-alias to owl.version but reports key: 'version'" do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", "schema_version: 1\nproject:\n  id: sample\nowl:\n  version: '9.9.9'\n")
        result = described_class.read_key(root: root, key: 'version')
        expect(result).to be_ok
        expect(result.value).to eq(key: 'version', value: '9.9.9')

        canonical = described_class.read_key(root: root, key: 'owl.version')
        expect(canonical.value[:value]).to eq('9.9.9')
      end
    end

    it 'returns config_key_missing through the version alias on a legacy project without owl.version' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_config)
        result = described_class.read_key(root: root, key: 'version')
        expect(result).to be_err
        expect(result.code).to eq(:config_key_missing)
      end
    end
  end

  describe '.write_key' do
    it "rejects writes to the read-only 'version' alias with config_key_aliased" do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_config)
        result = described_class.write_key(root: root, key: 'version', value: '9.9.9')
        expect(result).to be_err
        expect(result.code).to eq(:config_key_aliased)
        expect(result.message).to include('owl.version')
      end
    end

    it 'writes a string value and persists it' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_config)
        result = described_class.write_key(root: root, key: 'settings.language.communication', value: 'ru')
        expect(result).to be_ok
        expect(result.value).to eq(key: 'settings.language.communication', value: 'ru')

        reread = described_class.read_key(root: root, key: 'settings.language.communication')
        expect(reread.value[:value]).to eq('ru')
      end
    end

    it 'creates intermediate hash nodes when path does not exist' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_config)
        result = described_class.write_key(root: root, key: 'settings.workflows.enabled', value: '["feature","bugfix"]')
        expect(result).to be_ok
        expect(result.value[:value]).to eq(%w[feature bugfix])

        reread = described_class.read_key(root: root, key: 'settings.workflows.enabled')
        expect(reread.value[:value]).to eq(%w[feature bugfix])
      end
    end

    it 'writes non-settings paths now that the whitelist is removed' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_config)
        result = described_class.write_key(root: root, key: 'workflow.feature.phases', value: '["plan","implement"]')
        expect(result).to be_ok
        expect(result.value).to eq(key: 'workflow.feature.phases', value: %w[plan implement])

        reread = described_class.read_key(root: root, key: 'workflow.feature.phases')
        expect(reread.value[:value]).to eq(%w[plan implement])
      end
    end

    it 'refuses writes that would invalidate config (atomic rollback)' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_config)
        result = described_class.write_key(root: root, key: 'settings.storage.backend', value: 's3')
        expect(result).to be_err
        expect(result.code).to eq(:config_validation_failed)

        reread = described_class.read_key(root: root, key: 'settings.storage.backend')
        expect(reread.value[:value]).to eq('filesystem')
      end
    end

    it 'reports invalid JSON literal' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_config)
        result = described_class.write_key(root: root, key: 'settings.workflows.enabled', value: '[broken')
        expect(result).to be_err
        expect(result.code).to eq(:invalid_config_value)
      end
    end

    it 'reports invalid key shape' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_config)
        result = described_class.write_key(root: root, key: 'settings..language', value: 'x')
        expect(result).to be_err
        expect(result.code).to eq(:invalid_config_key)
      end
    end

    it 'propagates load errors as-is' do
      with_tmp_project do |root|
        result = described_class.write_key(root: root, key: 'settings.language.communication', value: 'ru')
        expect(result).to be_err
        expect(result.code).to eq(:config_missing)
      end
    end
  end

  describe '.snapshot' do
    it 'returns settings, storage profile, project, schema_version' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_config)
        result = described_class.snapshot(root: root)
        expect(result).to be_ok
        snapshot = result.value
        expect(snapshot[:schema_version]).to eq(1)
        expect(snapshot[:project]['id']).to eq('sample')
        expect(snapshot[:settings]['language']['communication']).to eq('en')
        expect(snapshot[:storage][:active_profile]).to eq('default')
        expect(snapshot[:storage][:roles_present]).to include('tasks', 'docs')
        expect(snapshot[:owl]).to be_a(Hash)
      end
    end

    it 'includes owl.version in the snapshot owl block when stamped' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", "schema_version: 1\nproject:\n  id: sample\nowl:\n  version: '9.9.9'\n")
        result = described_class.snapshot(root: root)
        expect(result).to be_ok
        expect(result.value[:owl]).to eq('version' => '9.9.9')
      end
    end

    it 'propagates load errors as-is' do
      with_tmp_project do |root|
        result = described_class.snapshot(root: root)
        expect(result).to be_err
        expect(result.code).to eq(:config_missing)
      end
    end
  end

  describe 'backend routing' do
    it 'delegates to the backend resolved by Owl::Internal::BackendResolver' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", valid_config)

        fake_backend = instance_double(Owl::Config::Backends::Filesystem)
        allow(Owl::Internal::BackendResolver).to receive(:resolve)
          .with(root: root, scope: :config)
          .and_return(Owl::Result.ok(fake_backend))
        allow(fake_backend).to receive(:load).and_return(Owl::Result.ok(:stub))

        result = described_class.load(root: root)

        expect(Owl::Internal::BackendResolver).to have_received(:resolve).with(root: root, scope: :config)
        expect(fake_backend).to have_received(:load)
        expect(result.value).to eq(:stub)
      end
    end

    it 'returns Filesystem-served result even when settings.storage.backend is unknown' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", <<~YAML)
          settings:
            language:
              communication: en
            storage:
              backend: imaginary
        YAML
        # Layer-C exception #2 keeps Config::Api.load reachable even with an
        # invalid storage backend value — required for `owl config validate`
        # to actually surface the schema error to the user.
        result = described_class.validate(root: root)
        expect(result).to be_err
        codes = result.details[:errors].map { |e| e[:code] }
        expect(codes).to include(:unsupported_settings_storage_backend)
      end
    end
  end
end
