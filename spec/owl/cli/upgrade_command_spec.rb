# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'owl upgrade / self-update CLI' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  describe 'owl upgrade' do
    it 'refreshes a stale managed file and reports it' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        File.write("#{root}/.owl/artifacts/plan/templates/default.md", "STALE\n")
        code, out, = run(['upgrade', '--root', root.to_s, '--json'], cwd: root)
        expect(code).to eq(0)
        body = JSON.parse(out)
        expect(body['ok']).to be(true)
        expect(body['replaced']).to include('.owl/artifacts/plan/templates/default.md')
      end
    end

    it 'supports --dry-run without writing' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        File.write("#{root}/.owl/artifacts/plan/templates/default.md", "STALE\n")
        code, out, = run(['upgrade', '--dry-run', '--root', root.to_s, '--json'], cwd: root)
        expect(code).to eq(0)
        expect(JSON.parse(out)['dry_run']).to be(true)
        expect(File.read("#{root}/.owl/artifacts/plan/templates/default.md")).to eq("STALE\n")
      end
    end

    it 'returns invalid_arguments on an unknown flag' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        code, _, err = run(['upgrade', '--bogus', '--root', root.to_s], cwd: root)
        expect(code).to eq(1)
        expect(JSON.parse(err).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'owl self-update' do
    it 'returns invalid_arguments on an unknown flag (before any network call)' do
      with_tmp_project do |root|
        code, _, err = run(['self-update', '--bogus'], cwd: root)
        expect(code).to eq(1)
        expect(JSON.parse(err).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end
end
