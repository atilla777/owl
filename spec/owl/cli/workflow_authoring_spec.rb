# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'owl workflow authoring CLI (source / context / register)' do
  def run(argv, cwd:, stdin: nil)
    stdout = StringIO.new
    stderr = StringIO.new
    with_stdin(stdin) do
      exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
      [exit_code, stdout.string, stderr.string]
    end
  end

  def with_stdin(content)
    return yield if content.nil?

    original = $stdin
    $stdin = StringIO.new(content)
    yield
  ensure
    $stdin = original if content
  end

  def setup_project(root)
    run(['init', '--root', root.to_s], cwd: root)
  end

  describe 'workflow source show' do
    it 'returns the raw workflow body' do
      with_tmp_project do |root|
        setup_project(root)
        code, out, = run(['workflow', 'source', 'show', 'feature', '--root', root.to_s, '--json'], cwd: root)
        expect(code).to eq(0)
        expect(JSON.parse(out)['body']).to include('id: feature')
      end
    end

    it 'returns unknown_command for an unknown source subcommand' do
      with_tmp_project do |root|
        setup_project(root)
        code, _, err = run(['workflow', 'source', 'frob', 'feature', '--root', root.to_s], cwd: root)
        expect(code).to eq(1)
        expect(JSON.parse(err).dig('error', 'code')).to eq('unknown_command')
      end
    end
  end

  describe 'workflow context show/set' do
    it 'shows a step context body' do
      with_tmp_project do |root|
        setup_project(root)
        code, out, = run(['workflow', 'context', 'show', 'feature', 'design', '--root', root.to_s, '--json'], cwd: root)
        expect(code).to eq(0)
        expect(JSON.parse(out)['body']).not_to be_empty
      end
    end

    it 'refuses to set a managed workflow context' do
      with_tmp_project do |root|
        setup_project(root)
        code, _, err = run(['workflow', 'context', 'set', 'feature', 'design', '--body', '-', '--root', root.to_s],
                           cwd: root, stdin: "x\n")
        expect(code).to eq(1)
        expect(JSON.parse(err).dig('error', 'code')).to eq('workflow_managed')
      end
    end

    it 'sets a project-owned workflow context after cloning' do
      with_tmp_project do |root|
        setup_project(root)
        run(['workflow', 'new', '--from', 'feature', '--id', 'cust_flow', '--register', '--root', root.to_s], cwd: root)
        code, out, = run(['workflow', 'context', 'set', 'cust_flow', 'design', '--body', '-', '--root', root.to_s],
                         cwd: root, stdin: "fresh design\n")
        expect(code).to eq(0)
        expect(JSON.parse(out)['ok']).to be(true)

        _, show, = run(['workflow', 'context', 'show', 'cust_flow', 'design', '--root', root.to_s, '--json'], cwd: root)
        expect(JSON.parse(show)['body']).to eq("fresh design\n")
      end
    end

    it 'returns invalid_arguments when STEP is missing' do
      with_tmp_project do |root|
        setup_project(root)
        code, _, err = run(['workflow', 'context', 'show', 'feature', '--root', root.to_s], cwd: root)
        expect(code).to eq(1)
        expect(JSON.parse(err).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'workflow register / unregister' do
    it 'registers and unregisters a workflow' do
      with_tmp_project do |root|
        setup_project(root)
        run(['workflow', 'new', '--id', 'temp_flow', '--root', root.to_s], cwd: root)
        code, out, = run(['workflow', 'register', 'temp_flow', '--root', root.to_s, '--json'], cwd: root)
        expect(code).to eq(0)
        expect(JSON.parse(out)['managed']).to be(false)

        code, out, = run(['workflow', 'unregister', 'temp_flow', '--root', root.to_s, '--json'], cwd: root)
        expect(code).to eq(0)
        expect(JSON.parse(out)['ok']).to be(true)
      end
    end

    it 'fails register with invalid_arguments when ID missing' do
      with_tmp_project do |root|
        setup_project(root)
        code, _, err = run(['workflow', 'register', '--root', root.to_s], cwd: root)
        expect(code).to eq(1)
        expect(JSON.parse(err).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end
end
