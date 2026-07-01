# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

RSpec.describe Owl::Cli::Api do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = described_class.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  describe '--help' do
    it 'prints usage to stderr and exits 0 without polluting stdout' do
      with_tmp_project do |root|
        exit_code, stdout, stderr = run(%w[--help], cwd: root)
        expect(exit_code).to eq(0)
        expect(stdout).to eq('')
        expect(stderr).to include('Usage: owl')
      end
    end

    it 'with no arguments behaves like --help' do
      with_tmp_project do |root|
        exit_code, stdout, stderr = run([], cwd: root)
        expect(exit_code).to eq(0)
        expect(stdout).to eq('')
        expect(stderr).to include('Usage: owl')
      end
    end
  end

  describe '--version' do
    it 'prints the version to stderr' do
      with_tmp_project do |root|
        exit_code, stdout, stderr = run(%w[--version], cwd: root)
        expect(exit_code).to eq(0)
        expect(stdout).to eq('')
        expect(stderr).to include("owl #{Owl::VERSION}")
      end
    end
  end

  describe 'unknown commands' do
    it 'reports an unknown top-level command as a structured error' do
      with_tmp_project do |root|
        exit_code, stdout, stderr = run(%w[nope], cwd: root)
        expect(exit_code).to eq(1)
        expect(stdout).to eq('')
        body = JSON.parse(stderr)
        expect(body['ok']).to be(false)
        expect(body['error']['code']).to eq('unknown_command')
      end
    end

    it 'reports an unknown workflow subcommand' do
      with_tmp_project do |root|
        exit_code, _stdout, stderr = run(%w[workflow nope], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_command')
      end
    end

    it 'reports an unknown config subcommand' do
      with_tmp_project do |root|
        exit_code, _stdout, stderr = run(%w[config nope], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_command')
      end
    end

    it 'reports an unknown task child subcommand' do
      with_tmp_project do |root|
        exit_code, _stdout, stderr = run(%w[task child nope], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_command')
      end
    end
  end

  describe 'group subcommand help (TASK-0023 FF1)' do
    it 'prints the step subcommand list and exits 0 for a bare group command' do
      with_tmp_project do |root|
        exit_code, stdout, stderr = run(%w[step], cwd: root)
        expect(exit_code).to eq(0)
        expect(stdout).to eq('')
        expect(stderr).to include('Usage: owl step <subcommand>')
        expect(stderr).to include('Subcommands:')
        expect(stderr).to include('start', 'complete', 'reopen', 'report')
      end
    end

    it 'prints the step subcommand list for `step --help` and exits 0' do
      with_tmp_project do |root|
        exit_code, stdout, stderr = run(%w[step --help], cwd: root)
        expect(exit_code).to eq(0)
        expect(stdout).to eq('')
        expect(stderr).to include('Subcommands:')
        expect(stderr).to include('skip')
      end
    end

    it 'emits a machine-readable subcommand list under --json' do
      with_tmp_project do |root|
        exit_code, stdout, stderr = run(%w[step --help --json], cwd: root)
        expect(exit_code).to eq(0)
        expect(stderr).to eq('')
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['command']).to eq('step')
        expect(body['subcommands']).to include('start', 'complete', 'report')
      end
    end

    it 'still reports an unknown concrete subcommand as unknown_command' do
      with_tmp_project do |root|
        exit_code, stdout, stderr = run(%w[step bogus], cwd: root)
        expect(exit_code).to eq(1)
        expect(stdout).to eq('')
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_command')
      end
    end

    it 'prints subcommands for the other registered groups' do
      with_tmp_project do |root|
        %w[task workflow artifact].each do |group|
          exit_code, _stdout, stderr = run([group, '--help'], cwd: root)
          expect(exit_code).to eq(0), "#{group} --help should exit 0"
          expect(stderr).to include('Subcommands:'), "#{group} --help should list subcommands"
        end
      end
    end

    it 'does not treat a bare-arg group (archive) as a subcommand group' do
      with_tmp_project do |root|
        _exit_code, _stdout, stderr = run(%w[archive], cwd: root)
        expect(stderr).not_to include('Subcommands:')
      end
    end
  end

  describe 'owl init' do
    it 'creates the default layout plus seeded workflow and artifact templates' do
      with_tmp_project do |root|
        exit_code, stdout, _stderr = run(['init', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)

        base = %w[
          .owl/config.yaml
          .owl/workflows.yaml
          .owl/artifacts.yaml
          tasks/index.yaml
          docs/.keep
        ]
        overlay_steps = %w[brief design plan implement review_code merge_docs archive commit_push]
        session_overlays = %w[orchestrator]
        overlays = (overlay_steps + session_overlays).map { |s| ".owl/overlays/#{s}.md" }
        workflow_sources = Owl::Workflows::Api.seeded_sources.map { |f| f[:relative_path] }
        artifact_sources = Owl::Artifacts::Api.seeded_sources.map { |f| f[:relative_path] }
        skill_sources = Owl::Skills::Api.seeded_sources.map { |f| f[:relative_path] }
        expected = base + overlays + workflow_sources + artifact_sources + skill_sources

        expected.each do |rel|
          expect((root + rel).exist?).to be(true), "missing #{rel}"
        end
        expect(body['created'].length).to eq(expected.length)
        expect(body['skipped']).to eq([])
      end
    end

    it 'skips existing files without --force' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(['init', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['created']).to eq([])
        expect(body['skipped']).not_to be_empty
      end
    end

    it 'refreshes seed bodies but preserves user state with --force' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        skill_path = Pathname.new("#{root}/.claude/skills/owl-orchestrator/SKILL.md")
        skill_path.write("# mutated\n")

        exit_code, stdout, _stderr = run(['init', '--root', root.to_s, '--force'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        # User state (config, registries, index) is preserved; seed bodies refresh.
        expect(body['skipped']).to include(a_string_ending_with('/.owl/config.yaml'))
        expect(body['created']).to include(skill_path.to_s)
        expect(skill_path.read).not_to eq("# mutated\n")
      end
    end

    it 'reports invalid option flags as a structured error' do
      with_tmp_project do |root|
        exit_code, _stdout, stderr = run(['init', '--bogus'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'owl workflow list --json' do
    it 'returns the five seeded workflows on a freshly initialized project' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(['workflow', 'list', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['workflows'].map { |w| w['key'] }).to contain_exactly(
          'feature', 'composite_feature', 'hotfix', 'refactor', 'quick'
        )
        expect(body['workflows']).to all(include('source_present' => true))
      end
    end

    it 'returns a structured error when no .owl/ directory can be detected' do
      with_tmp_project do |root|
        Dir.chdir(root.to_s) do
          exit_code, stdout, stderr = run(['workflow', 'list', '--json'], cwd: root)
          expect(exit_code).to eq(1)
          expect(stdout).to eq('')
          expect(JSON.parse(stderr).dig('error', 'code')).to eq('project_root_not_found')
        end
      end
    end

    it 'reports invalid option flags as a structured error' do
      with_tmp_project do |root|
        exit_code, _stdout, stderr = run(['workflow', 'list', '--bogus'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'owl config validate --json' do
    it 'returns valid: true on a freshly initialized project' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(['config', 'validate', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['valid']).to be(true)
        expect(body['schema_version']).to eq(1)
        expect(body.dig('storage', 'active_profile')).to eq('default')
        expect(body.dig('storage', 'roles_present')).to include(*Owl::Storage::Api::STANDARD_ROLES)
        expect(body.dig('workflows', 'count')).to eq(5)
        expect(body.dig('artifacts', 'count')).to eq(8)
        expect(body['errors']).to eq([])
      end
    end

    it 'returns valid: false when config has missing role' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", <<~YAML)
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
        write("#{root}/.owl/workflows.yaml", Owl::Workflows::Api.default_template)
        write("#{root}/.owl/artifacts.yaml", Owl::Artifacts::Api.default_template)

        exit_code, stdout, _stderr = run(['config', 'validate', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['valid']).to be(false)
        codes = body['errors'].map { |e| e['code'] }
        expect(codes).to include('missing_role')
      end
    end

    it 'returns a structured error when no .owl/ directory can be detected' do
      with_tmp_project do |root|
        exit_code, stdout, stderr = run(['config', 'validate', '--json'], cwd: root)
        expect(exit_code).to eq(1)
        expect(stdout).to eq('')
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('project_root_not_found')
      end
    end

    it 'reports invalid option flags as a structured error' do
      with_tmp_project do |root|
        exit_code, _stdout, stderr = run(['config', 'validate', '--bogus'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'owl config get' do
    it 'returns ok: true with key/value for a settings.* dot-path' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(
          ['config', 'get', 'settings.language.communication', '--root', root.to_s, '--json'], cwd: root
        )
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body).to include('ok' => true, 'key' => 'settings.language.communication', 'value' => 'en')
      end
    end

    it 'reads a non-settings path (project.id) after the whitelist is removed' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(['config', 'get', 'project.id', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body).to include('ok' => true, 'key' => 'project.id')
        expect(body['value']).not_to be_nil
      end
    end

    it 'returns ok with value: null for an unknown leaf (default missing-key semantics)' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, stderr = run(['config', 'get', 'settings.language.bogus', '--root', root.to_s, '--json'],
                                        cwd: root)
        expect(exit_code).to eq(0)
        expect(stderr).to eq('')
        expect(JSON.parse(stdout)).to eq('ok' => true, 'key' => 'settings.language.bogus', 'value' => nil)
      end
    end

    it 'returns the legacy config_key_missing error under --strict' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(
          ['config', 'get', 'settings.language.bogus', '--strict', '--root', root.to_s, '--json'], cwd: root
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('config_key_missing')
      end
    end

    it 'reports invalid_arguments when KEY is omitted' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(['config', 'get', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'reports invalid option flags as a structured error' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(['config', 'get', '--bogus'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'reports project_root_not_found when no .owl/ is detectable' do
      with_tmp_project do |root|
        exit_code, _stdout, stderr = run(['config', 'get', 'settings.language.communication', '--json'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('project_root_not_found')
      end
    end
  end

  describe 'owl config set' do
    it 'persists a string value at a settings.* dot-path' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(
          ['config', 'set', 'settings.language.communication', 'ru', '--root', root.to_s, '--json'], cwd: root
        )
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body).to include('ok' => true, 'key' => 'settings.language.communication', 'value' => 'ru')

        verify_code, verify_stdout, _stderr = run(
          ['config', 'get', 'settings.language.communication', '--root', root.to_s, '--json'], cwd: root
        )
        expect(verify_code).to eq(0)
        expect(JSON.parse(verify_stdout)['value']).to eq('ru')
      end
    end

    it 'persists a JSON-array value' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(
          ['config', 'set', 'settings.workflows.enabled', '["feature","bugfix"]', '--root', root.to_s,
           '--json'], cwd: root
        )
        expect(exit_code).to eq(0)
        expect(JSON.parse(stdout)['value']).to eq(%w[feature bugfix])
      end
    end

    it 'rejects writes that would invalidate config (atomic rollback)' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(
          ['config', 'set', 'settings.storage.backend', 's3', '--root', root.to_s, '--json'], cwd: root
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('config_validation_failed')

        verify_code, verify_stdout, _stderr = run(
          ['config', 'get', 'settings.storage.backend', '--root', root.to_s, '--json'], cwd: root
        )
        expect(verify_code).to eq(0)
        expect(JSON.parse(verify_stdout)['value']).to eq('filesystem')
      end
    end

    it 'writes a non-settings path (workflow.feature.phases) after the whitelist is removed' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(
          ['config', 'set', 'workflow.feature.phases', '["plan","implement"]', '--root', root.to_s, '--json'],
          cwd: root
        )
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body).to include('ok' => true, 'key' => 'workflow.feature.phases', 'value' => %w[plan implement])

        verify_code, verify_stdout, _stderr = run(
          ['config', 'get', 'workflow.feature.phases', '--root', root.to_s, '--json'], cwd: root
        )
        expect(verify_code).to eq(0)
        expect(JSON.parse(verify_stdout)['value']).to eq(%w[plan implement])
      end
    end

    it 'reports invalid JSON literal' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(
          ['config', 'set', 'settings.workflows.enabled', '[broken', '--root', root.to_s, '--json'], cwd: root
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_config_value')
      end
    end

    it 'reports invalid_arguments when KEY or VALUE is omitted' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(
          ['config', 'set', 'settings.language.communication', '--root', root.to_s, '--json'], cwd: root
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'reports invalid option flags as a structured error' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(['config', 'set', '--bogus'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'reports project_root_not_found when no .owl/ is detectable' do
      with_tmp_project do |root|
        exit_code, _stdout, stderr = run(['config', 'set', 'settings.language.communication', 'ru', '--json'],
                                         cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('project_root_not_found')
      end
    end
  end

  describe 'owl config — TD-141 regression freeze: path symmetry + missing-key semantics' do
    it 'reproduces the four specification Reproduce Steps after the fix' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)

        # Step 1: read a non-settings path; whitelist must be gone.
        # The seeded template may or may not populate workflow.feature.phases — both outcomes
        # prove the whitelist is gone (no :unsupported_config_path failure).
        code1, stdout1, stderr1 = run(
          ['config', 'get', 'workflow.feature.phases', '--root', root.to_s, '--json'], cwd: root
        )
        expect(code1).to eq(0), "expected ok exit, got #{code1}; stderr=#{stderr1}"
        body1 = JSON.parse(stdout1)
        expect(body1).to include('ok' => true, 'key' => 'workflow.feature.phases')
        expect(stderr1).to eq('')

        # Step 2: read a definitely-missing key; default semantics return ok + value:null, exit 0.
        code2, stdout2, stderr2 = run(
          ['config', 'get', 'nonexistent.key.path', '--root', root.to_s, '--json'], cwd: root
        )
        expect(code2).to eq(0)
        expect(stderr2).to eq('')
        expect(JSON.parse(stdout2)).to eq('ok' => true, 'key' => 'nonexistent.key.path', 'value' => nil)

        # Step 3: --strict flips back to the legacy :config_key_missing error.
        code3, stdout3, stderr3 = run(
          ['config', 'get', 'nonexistent.key.path', '--strict', '--root', root.to_s, '--json'], cwd: root
        )
        expect(code3).to eq(1)
        expect(stdout3).to eq('')
        expect(JSON.parse(stderr3).dig('error', 'code')).to eq('config_key_missing')

        # Step 4: write a non-settings path; whitelist must be gone for writes too;
        # round-trip via get must return the same value.
        code4, stdout4, stderr4 = run(
          ['config', 'set', 'workflow.feature.phases', '["a","b"]', '--root', root.to_s, '--json'], cwd: root
        )
        expect(code4).to eq(0), "expected ok exit on set, got #{code4}; stderr=#{stderr4}"
        expect(JSON.parse(stdout4)).to include(
          'ok' => true, 'key' => 'workflow.feature.phases', 'value' => %w[a b]
        )

        code4b, stdout4b, _stderr4b = run(
          ['config', 'get', 'workflow.feature.phases', '--root', root.to_s, '--json'], cwd: root
        )
        expect(code4b).to eq(0)
        expect(JSON.parse(stdout4b)['value']).to eq(%w[a b])
      end
    end
  end

  describe 'owl config show' do
    it 'returns a JSON snapshot with settings and storage info' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(['config', 'show', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['schema_version']).to eq(1)
        expect(body.dig('settings', 'language', 'communication')).to eq('en')
        expect(body.dig('settings', 'storage', 'backend')).to eq('filesystem')
        expect(body.dig('storage', 'active_profile')).to eq('default')
        expect(body.dig('storage', 'roles_present')).to include('tasks', 'docs')
        expect(body.dig('owl', 'version')).to eq(Owl::VERSION)
      end
    end

    it 'reports config_missing when there is no config file' do
      with_tmp_project do |root|
        write("#{root}/.owl/.keep", '')
        exit_code, _stdout, stderr = run(['config', 'show', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('config_missing')
      end
    end

    it 'reports invalid option flags as a structured error' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(['config', 'show', '--bogus'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'reports project_root_not_found when no .owl/ is detectable' do
      with_tmp_project do |root|
        exit_code, _stdout, stderr = run(['config', 'show', '--json'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('project_root_not_found')
      end
    end
  end

  describe 'owl version (subcommand)' do
    it 'prints gem, project and up_to_date as JSON on a freshly initialized project' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(['version', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body).to include('ok' => true, 'gem' => Owl::VERSION, 'project' => Owl::VERSION, 'up_to_date' => true)
        expect(body).to have_key('self_hosted')
        expect(body['self_hosted']).to be(false)
      end
    end

    it 'coexists with the --version gem flag (which only prints the gem)' do
      with_tmp_project do |root|
        exit_code, stdout, stderr = run(%w[--version], cwd: root)
        expect(exit_code).to eq(0)
        expect(stdout).to eq('')
        expect(stderr).to include("owl #{Owl::VERSION}")
      end
    end

    it 'reports project_root_not_found when no .owl/ is detectable' do
      with_tmp_project do |root|
        exit_code, _stdout, stderr = run(['version', '--json'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('project_root_not_found')
      end
    end
  end

  describe 'owl config get version (read alias)' do
    it 'returns the stamped owl.version instead of null' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(['config', 'get', 'version', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body).to include('ok' => true, 'key' => 'version', 'value' => Owl::VERSION)
        expect(body['value']).not_to be_nil
      end
    end
  end

  describe 'owl config set version (rejected alias)' do
    it 'rejects writes to the read-only version alias with config_key_aliased' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, stderr = run(['config', 'set', 'version', '9.9.9', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(1)
        expect(stdout).to eq('')
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('config_key_aliased')
      end
    end
  end

  describe 'owl workflow new --id ID' do
    it 'scaffolds a task-kind workflow source by default' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(
          ['workflow', 'new', '--id', 'demo', '--kind', 'task', '--root', root.to_s, '--json'], cwd: root
        )
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['id']).to eq('demo')
        expect(body['kind']).to eq('task')
        expect(File.exist?(body['path'])).to be(true)
      end
    end

    it 'refuses to overwrite existing source without --force' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        run(['workflow', 'new', '--id', 'dupe', '--root', root.to_s, '--json'], cwd: root)
        exit_code, _stdout, stderr = run(['workflow', 'new', '--id', 'dupe', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('workflow_already_exists')
      end
    end

    it 'rejects an invalid id with invalid_workflow_id' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(['workflow', 'new', '--id', 'Bad-Id', '--root', root.to_s, '--json'],
                                         cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_workflow_id')
      end
    end

    it 'reports invalid_arguments when --id is missing' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(['workflow', 'new', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'owl workflow validate ID-OR-PATH' do
    it 'returns ok for a registered seeded workflow' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(['workflow', 'validate', 'feature', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        expect(JSON.parse(stdout)['valid']).to be(true)
      end
    end

    it 'validates a freshly scaffolded workflow by path' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        scaffold_exit, scaffold_out, = run(['workflow', 'new', '--id', 'pathval', '--root', root.to_s, '--json'],
                                           cwd: root)
        expect(scaffold_exit).to eq(0)
        path = JSON.parse(scaffold_out)['path']
        exit_code, stdout, _stderr = run(['workflow', 'validate', path, '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        expect(JSON.parse(stdout)['valid']).to be(true)
      end
    end

    it 'reports invalid_arguments when no target is given' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(['workflow', 'validate', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'owl workflow show ID' do
    it 'returns the definition body for a seeded workflow' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(['workflow', 'show', 'feature', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['id']).to eq('feature')
        expect(body.dig('definition', 'steps')).to be_an(Array)
      end
    end

    it 'reports unknown_workflow for an unregistered id' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(['workflow', 'show', 'nope', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_workflow')
      end
    end
  end

  describe 'owl artifact-type list' do
    it 'returns the eight seeded artifact types on a fresh project' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(['artifact-type', 'list', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        keys = JSON.parse(stdout)['artifact_types'].map { |a| a['key'] }
        expect(keys).to contain_exactly(
          'brief', 'design', 'plan', 'review', 'decomposition', 'verification', 'spec', 'spec_delta'
        )
      end
    end
  end

  describe 'owl artifact-type new --id ID' do
    it 'scaffolds a new artifact-type source' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(['artifact-type', 'new', '--id', 'demo_at', '--root', root.to_s, '--json'],
                                         cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['id']).to eq('demo_at')
        expect(File.exist?(body['path'])).to be(true)
        expect(File.exist?(body['template_path'])).to be(true)
      end
    end

    it 'rejects a duplicate id without --force' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        run(['artifact-type', 'new', '--id', 'dup_at', '--root', root.to_s, '--json'], cwd: root)
        exit_code, _stdout, stderr = run(['artifact-type', 'new', '--id', 'dup_at', '--root', root.to_s, '--json'],
                                         cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('artifact_type_already_exists')
      end
    end

    it 'reports invalid_arguments when --id is missing' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(['artifact-type', 'new', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'owl artifact-type validate ID-OR-PATH' do
    it 'returns ok for a seeded artifact-type' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(['artifact-type', 'validate', 'brief', '--root', root.to_s, '--json'],
                                         cwd: root)
        expect(exit_code).to eq(0)
        expect(JSON.parse(stdout)['valid']).to be(true)
      end
    end

    it 'reports invalid_arguments when no target is given' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(['artifact-type', 'validate', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'owl artifact-type show ID' do
    it 'returns the definition body for a seeded artifact-type' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(['artifact-type', 'show', 'brief', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['id']).to eq('brief')
        expect(body.dig('definition', 'title')).to eq('Brief')
      end
    end

    it 'reports unknown_artifact_type for an unregistered id' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(['artifact-type', 'show', 'nope', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_artifact_type')
      end
    end

    it 'reports unknown subcommand for an unknown artifact-type verb' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(['artifact-type', 'nope', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_command')
      end
    end
  end
end
