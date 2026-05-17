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
  end

  describe 'owl init' do
    it 'creates exactly the default Stage 1 layout in an empty directory' do
      with_tmp_project do |root|
        exit_code, stdout, _stderr = run(['init', '--root', root.to_s], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)

        expected = %w[
          .owl/config.yaml
          .owl/workflows.yaml
          .owl/artifacts.yaml
          tasks/index.yaml
          docs/.keep
        ]
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
    it 'returns an empty workflows array on a freshly initialized project' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(['workflow', 'list', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['workflows']).to eq([])
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
        expect(body.dig('workflows', 'count')).to eq(0)
        expect(body.dig('artifacts', 'count')).to eq(0)
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
end
