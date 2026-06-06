# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'owl spec CLI' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def init_project(root)
    run(['init', '--root', root.to_s], cwd: root)
  end

  def template_body(root)
    Pathname.new("#{root}/.owl/artifacts/spec/templates/default.md").read
  end

  def seed_spec(root, domain, body)
    write("#{root}/specs/#{domain}/spec.md", body)
  end

  describe 'spec path' do
    it 'routes to SpecPath and returns the resolved path' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, stdout, = run(['spec', 'path', 'ui', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['domain']).to eq('ui')
        expect(body['path']).to eq("#{root}/specs/ui/spec.md")
      end
    end

    it 'requires the DOMAIN positional argument' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(['spec', 'path', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).not_to eq(0)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'rejects an unsafe domain with invalid_domain' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(['spec', 'path', '../x', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).not_to eq(0)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_domain')
      end
    end
  end

  describe 'spec list' do
    it 'routes to SpecList and returns the populated catalog' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root, 'ui', template_body(root))
        exit_code, stdout, = run(['spec', 'list', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['specs']).to eq([{ 'domain' => 'ui', 'path' => "#{root}/specs/ui/spec.md" }])
      end
    end
  end

  describe 'spec show' do
    it 'returns JSON by default' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root, 'ui', "hello body\n")
        exit_code, stdout, = run(['spec', 'show', 'ui', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['body']).to eq("hello body\n")
      end
    end

    it 'prints the raw body with --no-json' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root, 'ui', "hello body\n")
        exit_code, stdout, = run(['spec', 'show', 'ui', '--root', root.to_s, '--no-json'], cwd: root)
        expect(exit_code).to eq(0)
        expect(stdout).to eq("hello body\n")
      end
    end

    it 'requires the DOMAIN positional argument' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(['spec', 'show', '--root', root.to_s], cwd: root)
        expect(exit_code).not_to eq(0)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'spec validate' do
    it 'routes to SpecValidate and reports valid for the seeded template' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root, 'ui', template_body(root))
        exit_code, stdout, = run(['spec', 'validate', 'ui', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['valid']).to be(true)
        expect(body.dig('spec', 'domain')).to eq('ui')
      end
    end

    it 'requires the DOMAIN positional argument' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(['spec', 'validate', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).not_to eq(0)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'unknown spec subcommand' do
    it 'reports unknown_command' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(['spec', 'bogus', '--root', root.to_s], cwd: root)
        expect(exit_code).not_to eq(0)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('unknown_command')
      end
    end
  end
end
