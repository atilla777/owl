# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

require_relative '../../result'
require_relative '../../version'
require_relative 'shell_runner'

module Owl
  module Upgrade
    module Internal
      # Self-updates the owl-cli gem from github main (clone → build → install).
      # `gem install` cannot install from a git URL natively, so we clone a
      # shallow copy, `gem build` the gemspec, and `gem install` the built .gem.
      module SelfUpdate
        REPO_URL = 'https://github.com/atilla777/owl.git'
        VERSION_RE = /VERSION\s*=\s*['"]([^'"]+)['"]/

        module_function

        def call(check: false, runner: ShellRunner, dir_factory: nil)
          dir = (dir_factory || method(:default_mktmpdir)).call
          begin
            clone = runner.run(['git', 'clone', '--depth', '1', '--branch', 'main', REPO_URL, dir])
            return clone_error(clone) unless clone.ok

            latest = remote_version(dir)
            return remote_version_error(dir) if latest.nil?

            return check_result(latest) if check

            install(runner: runner, dir: dir, latest: latest)
          ensure
            FileUtils.remove_entry(dir) if dir && File.directory?(dir)
          end
        end

        def install(runner:, dir:, latest:)
          build = runner.run(['gem', 'build', 'owl-cli.gemspec'], chdir: dir)
          return build_error(build) unless build.ok

          gem_file = "owl-cli-#{latest}.gem"
          inst = runner.run(['gem', 'install', gem_file], chdir: dir)
          return install_error(inst) unless inst.ok

          Result.ok(action: 'installed', previous: Owl::VERSION, installed: latest)
        end

        def check_result(latest)
          Result.ok(
            action: 'check',
            current: Owl::VERSION,
            latest: latest,
            up_to_date: latest == Owl::VERSION
          )
        end

        def remote_version(dir)
          path = File.join(dir, 'lib', 'owl', 'version.rb')
          return nil unless File.exist?(path)

          match = File.read(path).match(VERSION_RE)
          match && match[1]
        end

        def default_mktmpdir
          Dir.mktmpdir('owl-self-update')
        end

        def clone_error(outcome)
          Result.err(code: :self_update_clone_failed,
                     message: "Failed to clone #{REPO_URL} (main): #{outcome.stderr.strip}",
                     details: { stderr: outcome.stderr })
        end

        def remote_version_error(_dir)
          Result.err(code: :self_update_version_unreadable,
                     message: 'Could not read lib/owl/version.rb from the cloned repository.')
        end

        def build_error(outcome)
          Result.err(code: :self_update_build_failed,
                     message: "`gem build owl-cli.gemspec` failed: #{outcome.stderr.strip}",
                     details: { stderr: outcome.stderr })
        end

        def install_error(outcome)
          Result.err(code: :self_update_install_failed,
                     message: "`gem install` failed: #{outcome.stderr.strip}. " \
                              'If installed under a managed Ruby or bundler, run the install manually ' \
                              '(may need sudo or a bundle update).',
                     details: { stderr: outcome.stderr })
        end
      end
    end
  end
end
