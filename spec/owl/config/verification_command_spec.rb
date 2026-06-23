# frozen_string_literal: true

require 'owl/config/api'

# `settings.verification.*` is project-scoped config (not a managed workflow or
# artifact definition). Validates shape + value rules and that the command is
# read back from `.owl/config.yaml`.
RSpec.describe 'settings.verification config' do
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

  def lang_only
    "#{base_config_without_settings}settings:\n  language:\n    communication: en\n"
  end

  def with_verification(block)
    "#{lang_only}  verification:\n#{block}"
  end

  def write_cfg(root, body)
    write("#{root}/.owl/config.yaml", body)
  end

  def codes(result)
    result.details[:errors].map { |e| e[:code] }
  end

  it 'accepts a valid command and timeout' do
    with_tmp_project do |root|
      write_cfg(root, with_verification("    command: \"bundle exec rspec\"\n    timeout_seconds: 600\n"))
      expect(Owl::Config::Api.validate(root: root)).to be_ok
    end
  end

  it 'accepts an absent verification block (opt-in)' do
    with_tmp_project do |root|
      write_cfg(root, lang_only)
      expect(Owl::Config::Api.validate(root: root)).to be_ok
    end
  end

  it 'rejects a non-mapping verification block' do
    with_tmp_project do |root|
      write_cfg(root, "#{lang_only}  verification: scalar\n")
      result = Owl::Config::Api.validate(root: root)
      expect(result).to be_err
      expect(codes(result)).to include(:invalid_settings_verification_shape)
    end
  end

  it 'rejects an empty command string' do
    with_tmp_project do |root|
      write_cfg(root, with_verification("    command: \"\"\n"))
      result = Owl::Config::Api.validate(root: root)
      expect(result).to be_err
      expect(codes(result)).to include(:invalid_settings_verification_command)
    end
  end

  it 'rejects a non-positive timeout' do
    with_tmp_project do |root|
      write_cfg(root, with_verification("    command: \"x\"\n    timeout_seconds: 0\n"))
      result = Owl::Config::Api.validate(root: root)
      expect(result).to be_err
      expect(codes(result)).to include(:invalid_settings_verification_timeout)
    end
  end

  it 'reads the command back from config (not from a workflow)' do
    with_tmp_project do |root|
      write("#{root}/.owl/config.yaml", with_verification("    command: \"bundle exec rspec\"\n"))
      read = Owl::Config::Api.read_key(root: root, key: 'settings.verification.command')
      expect(read).to be_ok
      expect(read.value[:value]).to eq('bundle exec rspec')
    end
  end
end
