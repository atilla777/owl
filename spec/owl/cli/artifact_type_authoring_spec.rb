# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'owl artifact-type authoring CLI (template / register / clone)' do
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

  describe 'artifact-type template show' do
    it 'prints a managed type template body' do
      with_tmp_project do |root|
        setup_project(root)
        code, out, = run(['artifact-type', 'template', 'show', 'plan', '--root', root.to_s, '--json'], cwd: root)
        expect(code).to eq(0)
        body = JSON.parse(out)
        expect(body['ok']).to be(true)
        expect(body['body']).to include('## Goal')
      end
    end

    it 'fails with invalid_arguments when ID is missing' do
      with_tmp_project do |root|
        setup_project(root)
        code, _, err = run(['artifact-type', 'template', 'show', '--root', root.to_s], cwd: root)
        expect(code).to eq(1)
        expect(JSON.parse(err).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'artifact-type template set' do
    it 'refuses a managed type' do
      with_tmp_project do |root|
        setup_project(root)
        code, _, err = run(['artifact-type', 'template', 'set', 'plan', '--body', '-', '--root', root.to_s],
                           cwd: root, stdin: "## Goal\n")
        expect(code).to eq(1)
        expect(JSON.parse(err).dig('error', 'code')).to eq('artifact_type_managed')
      end
    end

    it 'requires --body' do
      with_tmp_project do |root|
        setup_project(root)
        code, _, err = run(['artifact-type', 'template', 'set', 'plan', '--root', root.to_s], cwd: root)
        expect(code).to eq(1)
        expect(JSON.parse(err).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'writes a cloned project-owned type template' do
      with_tmp_project do |root|
        setup_project(root)
        run(['artifact-type', 'new', '--from', 'plan', '--id', 'cust_plan', '--register', '--root', root.to_s],
            cwd: root)
        code, out, = run(['artifact-type', 'template', 'set', 'cust_plan', '--body', '-', '--root', root.to_s],
                         cwd: root, stdin: "## Goal\nx\n## Checklist\n## Smoke test\n")
        expect(code).to eq(0)
        expect(JSON.parse(out)['ok']).to be(true)
      end
    end
  end

  describe 'artifact-type template validate' do
    it 'validates the seeded plan template' do
      with_tmp_project do |root|
        setup_project(root)
        code, out, = run(['artifact-type', 'template', 'validate', 'plan', '--root', root.to_s, '--json'], cwd: root)
        expect(code).to eq(0)
        expect(JSON.parse(out)['valid']).to be(true)
      end
    end
  end

  describe 'artifact-type template (unknown subcommand)' do
    it 'returns unknown_command' do
      with_tmp_project do |root|
        setup_project(root)
        code, _, err = run(['artifact-type', 'template', 'frobnicate', 'plan', '--root', root.to_s], cwd: root)
        expect(code).to eq(1)
        expect(JSON.parse(err).dig('error', 'code')).to eq('unknown_command')
      end
    end
  end

  describe 'artifact-type new --from --register' do
    it 'clones and registers in one step' do
      with_tmp_project do |root|
        setup_project(root)
        code, out, = run(['artifact-type', 'new', '--from', 'review', '--id', 'my_review',
                          '--register', '--root', root.to_s, '--json'], cwd: root)
        expect(code).to eq(0)
        body = JSON.parse(out)
        expect(body['registered']).to be(true)
        _, list, = run(['artifact-type', 'list', '--root', root.to_s, '--json'], cwd: root)
        keys = JSON.parse(list)['artifact_types'].map { |a| a['key'] }
        expect(keys).to include('my_review')
      end
    end
  end

  describe 'artifact-type register / unregister' do
    it 'registers then unregisters a type' do
      with_tmp_project do |root|
        setup_project(root)
        run(['artifact-type', 'new', '--id', 'temp_type', '--root', root.to_s], cwd: root)
        code, out, = run(['artifact-type', 'register', 'temp_type', '--root', root.to_s, '--json'], cwd: root)
        expect(code).to eq(0)
        expect(JSON.parse(out)['managed']).to be(false)

        code, out, = run(['artifact-type', 'unregister', 'temp_type', '--root', root.to_s, '--json'], cwd: root)
        expect(code).to eq(0)
        expect(JSON.parse(out)['ok']).to be(true)
      end
    end

    it 'fails register with invalid_arguments when ID missing' do
      with_tmp_project do |root|
        setup_project(root)
        code, _, err = run(['artifact-type', 'register', '--root', root.to_s], cwd: root)
        expect(code).to eq(1)
        expect(JSON.parse(err).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end
end
