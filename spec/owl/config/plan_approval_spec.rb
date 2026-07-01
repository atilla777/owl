# frozen_string_literal: true

require 'owl/config/api'

# `settings.plan_approval.required` is project-scoped config that makes the
# plan-approval checkpoint the default for new tasks. Validates shape + value.
RSpec.describe 'settings.plan_approval config' do
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

  def write_cfg(root, body)
    write("#{root}/.owl/config.yaml", body)
  end

  def codes(result)
    result.details[:errors].map { |e| e[:code] }
  end

  it 'accepts required: true' do
    with_tmp_project do |root|
      write_cfg(root, "#{lang_only}  plan_approval:\n    required: true\n")
      expect(Owl::Config::Api.validate(root: root)).to be_ok
    end
  end

  it 'accepts an absent plan_approval block (opt-in)' do
    with_tmp_project do |root|
      write_cfg(root, lang_only)
      expect(Owl::Config::Api.validate(root: root)).to be_ok
    end
  end

  it 'rejects a non-mapping plan_approval block' do
    with_tmp_project do |root|
      write_cfg(root, "#{lang_only}  plan_approval: scalar\n")
      result = Owl::Config::Api.validate(root: root)
      expect(result).to be_err
      expect(codes(result)).to include(:invalid_settings_plan_approval_shape)
    end
  end

  it 'rejects a non-boolean required value' do
    with_tmp_project do |root|
      write_cfg(root, "#{lang_only}  plan_approval:\n    required: yes-please\n")
      result = Owl::Config::Api.validate(root: root)
      expect(result).to be_err
      expect(codes(result)).to include(:invalid_settings_plan_approval_required)
    end
  end
end
