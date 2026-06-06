# frozen_string_literal: true

require 'fileutils'
require 'owl/upgrade/api'

RSpec.describe Owl::Upgrade::Api, '.self_update' do
  def outcome(success, stderr = '')
    Owl::Upgrade::Internal::ShellRunner::Outcome.new(success, '', stderr)
  end

  # Fake runner: simulates `git clone` by writing a version.rb into the clone
  # destination, and reports success/failure per step as configured.
  def runner(remote_version: '9.9.9', fail_on: nil)
    builder = method(:outcome)
    fake = Object.new
    fake.define_singleton_method(:run) do |cmd, chdir: nil| # rubocop:disable Lint/UnusedBlockArgument
      step = cmd[0..1] == %w[git clone] ? :clone : :"#{cmd[0]}_#{cmd[1]}"
      return builder.call(false, "boom: #{step}") if fail_on == step

      if step == :clone && remote_version
        dest = cmd.last
        FileUtils.mkdir_p(File.join(dest, 'lib', 'owl'))
        File.write(File.join(dest, 'lib', 'owl', 'version.rb'), "module Owl\n  VERSION = '#{remote_version}'\nend\n")
      end
      builder.call(true)
    end
    fake
  end

  describe 'check mode' do
    it 'reports the remote version and that an update is available' do
      result = described_class.self_update(check: true, runner: runner(remote_version: '9.9.9'))
      expect(result).to be_ok
      expect(result.value[:action]).to eq('check')
      expect(result.value[:latest]).to eq('9.9.9')
      expect(result.value[:current]).to eq(Owl::VERSION)
      expect(result.value[:up_to_date]).to be(false)
    end

    it 'reports up_to_date when versions match' do
      result = described_class.self_update(check: true, runner: runner(remote_version: Owl::VERSION))
      expect(result.value[:up_to_date]).to be(true)
    end
  end

  describe 'install mode' do
    it 'builds and installs the gem' do
      result = described_class.self_update(check: false, runner: runner(remote_version: '9.9.9'))
      expect(result).to be_ok
      expect(result.value[:action]).to eq('installed')
      expect(result.value[:installed]).to eq('9.9.9')
      expect(result.value[:previous]).to eq(Owl::VERSION)
    end
  end

  describe 'failures' do
    it 'errors when the clone fails' do
      result = described_class.self_update(runner: runner(fail_on: :clone))
      expect(result).to be_err
      expect(result.code).to eq(:self_update_clone_failed)
    end

    it 'errors when version.rb is unreadable' do
      result = described_class.self_update(runner: runner(remote_version: nil))
      expect(result).to be_err
      expect(result.code).to eq(:self_update_version_unreadable)
    end

    it 'errors when gem build fails' do
      result = described_class.self_update(runner: runner(fail_on: :gem_build))
      expect(result).to be_err
      expect(result.code).to eq(:self_update_build_failed)
    end

    it 'errors when gem install fails' do
      result = described_class.self_update(runner: runner(fail_on: :gem_install))
      expect(result).to be_err
      expect(result.code).to eq(:self_update_install_failed)
    end
  end
end
