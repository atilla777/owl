# frozen_string_literal: true

require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/config/api'
require 'owl/storage/api'
require 'owl/specs/api'

# Regression: existing `.owl/config.yaml` files predate the `specs` storage role.
# They must keep validating and must resolve `specs` to its default location,
# without the on-disk config being rewritten.
RSpec.describe 'specs role backward compatibility' do
  def init_project(root)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: ['init', '--root', root.to_s], stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s)
  end

  # Strip the specs role from a freshly-initialised config to mimic a legacy
  # project whose config was written before the role existed.
  def strip_specs_role(root)
    config_path = Pathname.new("#{root}/.owl/config.yaml")
    raw = YAML.safe_load(config_path.read)
    raw.dig('storage', 'profiles', 'default', 'roles')&.delete('specs')
    raw.dig('settings', 'storage', 'roles')&.delete('specs')
    config_path.write(YAML.dump(raw))
    config_path
  end

  it 'validates a config that has no specs role' do
    with_tmp_project do |root|
      init_project(root)
      config_path = strip_specs_role(root)
      expect(config_path.read).not_to include('specs')

      result = Owl::Config::Api.validate(root: root)
      expect(result).to be_ok
    end
  end

  it 'resolves the specs role to <root>/specs even when the config omits it' do
    with_tmp_project do |root|
      init_project(root)
      strip_specs_role(root)

      load_result = Owl::Config::Api.load(root: root)
      profile = load_result.value.active_profile
      resolved = Owl::Storage::Api.resolve(role: 'specs', profile: profile, root: root)
      expect(resolved).to be_ok
      expect(resolved.value.to_s).to eq("#{root}/specs")
    end
  end

  it 'lets Owl::Specs::Api.path work on a legacy config' do
    with_tmp_project do |root|
      init_project(root)
      strip_specs_role(root)

      result = Owl::Specs::Api.path(root: root, domain: 'ui')
      expect(result).to be_ok
      expect(result.value[:path]).to eq("#{root}/specs/ui/spec.md")
    end
  end

  it 'does not rewrite the on-disk config with the injected default' do
    with_tmp_project do |root|
      init_project(root)
      config_path = strip_specs_role(root)
      before = config_path.read

      Owl::Config::Api.validate(root: root)
      Owl::Storage::Api.resolve(
        role: 'specs',
        profile: Owl::Config::Api.load(root: root).value.active_profile,
        root: root
      )

      expect(config_path.read).to eq(before)
    end
  end
end
