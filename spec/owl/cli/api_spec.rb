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
        overlays = overlay_steps.map { |s| ".owl/overlays/#{s}.md" }
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

    it 'overwrites existing files with --force' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        config_path = Pathname.new("#{root}/.owl/config.yaml")
        config_path.write('tampered: true')

        exit_code, stdout, _stderr = run(['init', '--root', root.to_s, '--force'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['skipped']).to eq([])
        expect(config_path.read).to include('schema_version: 1')
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
    it 'returns the six seeded workflows on a freshly initialized project' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(['workflow', 'list', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['workflows'].map { |w| w['key'] }).to contain_exactly(
          'feature', 'composite_feature', 'feature_slice', 'hotfix', 'research', 'refactor'
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
        expect(body.dig('workflows', 'count')).to eq(6)
        expect(body.dig('artifacts', 'count')).to eq(12)
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

    it 'returns unsupported_config_path for non-settings keys' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(['config', 'get', 'project.id', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unsupported_config_path')
      end
    end

    it 'reports config_key_missing for unknown leaf' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(['config', 'get', 'settings.language.bogus', '--root', root.to_s, '--json'],
                                         cwd: root)
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

    it 'rejects non-settings paths' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, _stdout, stderr = run(['config', 'set', 'project.id', 'other', '--root', root.to_s, '--json'],
                                         cwd: root)
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unsupported_config_path')
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
    it 'returns the twelve seeded artifact types on a fresh project' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(['artifact-type', 'list', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        keys = JSON.parse(stdout)['artifact_types'].map { |a| a['key'] }
        expect(keys).to contain_exactly(
          'brief', 'design', 'plan', 'review', 'spec', 'tasks',
          'decomposition', 'verification', 'issue', 'patch_plan',
          'research_findings', 'recommendation'
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
