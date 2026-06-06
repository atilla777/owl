# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'owl overlay CLI' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  describe 'overlay list' do
    it 'lists candidate overlay paths' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        write("#{root}/.owl/overlays/plan.md", "note\n")
        code, out, = run(['overlay', 'list', 'plan', '--root', root.to_s, '--json'], cwd: root)
        expect(code).to eq(0)
        body = JSON.parse(out)
        expect(body['ok']).to be(true)
        expect(body['candidates'].first['present']).to be(true)
      end
    end

    it 'requires STEP-ID' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        code, _, err = run(['overlay', 'list', '--root', root.to_s], cwd: root)
        expect(code).to eq(1)
        expect(JSON.parse(err).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'overlay show' do
    it 'returns applied overlay bodies' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        write("#{root}/.owl/overlays/plan.md", "applied body\n")
        code, out, = run(['overlay', 'show', 'plan', '--root', root.to_s, '--json'], cwd: root)
        expect(code).to eq(0)
        body = JSON.parse(out)
        expect(body['overlays'].first['body']).to eq("applied body\n")
      end
    end
  end

  describe 'overlay validate' do
    it 'reports applied count and warnings' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        write("#{root}/.owl/overlays/plan.md", "ok\n")
        code, out, = run(['overlay', 'validate', 'plan', '--root', root.to_s, '--json'], cwd: root)
        expect(code).to eq(0)
        body = JSON.parse(out)
        expect(body['applied']).to eq(1)
        expect(body['warnings']).to eq([])
      end
    end
  end

  describe 'overlay (unknown subcommand)' do
    it 'returns unknown_command' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        code, _, err = run(['overlay', 'frob', 'plan', '--root', root.to_s], cwd: root)
        expect(code).to eq(1)
        expect(JSON.parse(err).dig('error', 'code')).to eq('unknown_command')
      end
    end
  end
end
