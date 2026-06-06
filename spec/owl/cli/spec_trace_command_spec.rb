# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'owl spec trace CLI' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def init_project(root)
    run(['init', '--root', root.to_s], cwd: root)
  end

  def seed_spec(root, domain, body)
    write("#{root}/specs/#{domain}/spec.md", body)
  end

  def traced_spec
    <<~MD
      ## Requirements

      ### Requirement: A
      The system SHALL do A.

      #### Scenario: One
      - WHEN x
      - THEN y
      - TEST: specs/demo/spec.md
    MD
  end

  def untraced_spec
    <<~MD
      ## Requirements

      ### Requirement: A
      The system SHALL do A.

      #### Scenario: No test
      - WHEN x
      - THEN y
    MD
  end

  it 'emits a JSON coverage report and exits 0 for a fully-traced spec' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root, 'demo', traced_spec)
      exit_code, stdout, = run(['spec', 'trace', 'demo', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      body = JSON.parse(stdout)
      expect(body['ok']).to be(true)
      expect(body['valid']).to be(true)
      expect(body['summary']['traced']).to eq(1)
    end
  end

  it 'exits non-zero under --strict when a scenario is untraced' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root, 'demo', untraced_spec)
      exit_code, stdout, = run(['spec', 'trace', 'demo', '--strict', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(1)
      body = JSON.parse(stdout)
      expect(body['ok']).to be(false)
      expect(body['untraced']).to eq([{ 'requirement' => 'A', 'scenario' => 'No test' }])
    end
  end

  it 'prints a readable ordered summary with --no-json' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root, 'demo', untraced_spec)
      exit_code, stdout, = run(['spec', 'trace', 'demo', '--no-json', '--root', root.to_s], cwd: root)
      expect(exit_code).to eq(0)
      expect(stdout).to include('Requirement: A')
      expect(stdout).to include('Scenario: No test — untraced')
      expect(stdout).to include('valid: false')
    end
  end

  it 'requires the DOMAIN positional argument' do
    with_tmp_project do |root|
      init_project(root)
      exit_code, _stdout, stderr = run(['spec', 'trace', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).not_to eq(0)
      expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
    end
  end

  it 'is read-only: tracing creates and modifies nothing under specs/' do
    with_tmp_project do |root|
      init_project(root)
      path = seed_spec(root, 'demo', untraced_spec)
      before = path.read
      before_entries = Pathname.new("#{root}/specs").glob('**/*').map(&:to_s).sort

      run(['spec', 'trace', 'demo', '--strict', '--root', root.to_s, '--json'], cwd: root)

      expect(path.read).to eq(before)
      expect(Pathname.new("#{root}/specs").glob('**/*').map(&:to_s).sort).to eq(before_entries)
    end
  end
end
