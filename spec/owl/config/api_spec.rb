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
  end
end
