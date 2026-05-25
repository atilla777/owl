# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'
require 'owl/steps/internal/active_step_lock'
require 'owl/subagents/internal/output_spec'

RSpec.describe 'owl step report CLI subcommand' do
  def run(argv, cwd:, stdin: StringIO.new)
    stdout = StringIO.new
    stderr = StringIO.new
    original_stdin = $stdin
    $stdin = stdin
    begin
      exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    ensure
      $stdin = original_stdin
    end
    [exit_code, stdout.string, stderr.string]
  end

  def init_project(root)
    run(['init', '--root', root.to_s], cwd: root)
  end

  let(:valid_report) do
    <<~MD
      ---
      status: returned_normally
      summary: "Done."
      session_type: execution
      ---

      ## Result

      Generated artifact.
    MD
  end

  describe 'write mode' do
    it 'writes a report from stdin' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, stdout, _stderr = run(
          ['step', 'report', '--task-id', 'TASK-1', '--step-id', 'plan', '--body', '-', '--root', root.to_s],
          cwd: root, stdin: StringIO.new(valid_report)
        )
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['path']).to end_with('.owl/local/reports/TASK-1/plan.md')
        path = root + '.owl/local/reports/TASK-1/plan.md'
        expect(path.read).to include('## Result')
      end
    end

    it 'writes a report from a file path' do
      with_tmp_project do |root|
        init_project(root)
        source = root + 'fixtures/report.md'
        source.dirname.mkpath
        source.write(valid_report)
        exit_code, stdout, _stderr = run(
          ['step', 'report', '--task-id', 'TASK-2', '--step-id', 'plan',
           '--body', source.to_s, '--root', root.to_s],
          cwd: root
        )
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect((root + '.owl/local/reports/TASK-2/plan.md').read).to eq(valid_report)
      end
    end

    it 'reports body_unreadable when the file path does not exist' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(
          ['step', 'report', '--task-id', 'TASK-3', '--step-id', 'plan',
           '--body', "#{root}/nope.md", '--root', root.to_s],
          cwd: root
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('body_unreadable')
      end
    end

    it 'validates frontmatter when --validate is passed (exit 2 on invalid)' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(
          ['step', 'report', '--task-id', 'TASK-4', '--step-id', 'plan',
           '--body', '-', '--validate', '--root', root.to_s],
          cwd: root, stdin: StringIO.new('not valid markdown')
        )
        expect(exit_code).to eq(2)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('missing_frontmatter')
      end
    end

    it 'rejects missing --task-id with no_current_task when no current.yaml or lock exists' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(
          ['step', 'report', '--step-id', 'plan', '--body', '-', '--root', root.to_s],
          cwd: root, stdin: StringIO.new(valid_report)
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('no_current_task')
      end
    end

    it 'rejects missing --body in write mode with invalid_arguments' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(
          ['step', 'report', '--task-id', 'TASK-5', '--step-id', 'plan', '--root', root.to_s],
          cwd: root
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'reports invalid_arguments for unknown options' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(
          ['step', 'report', '--bogus-flag', '--root', root.to_s],
          cwd: root
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'read mode' do
    it 'prints the saved report body on stdout' do
      with_tmp_project do |root|
        init_project(root)
        run(
          ['step', 'report', '--task-id', 'TASK-6', '--step-id', 'plan',
           '--body', '-', '--root', root.to_s],
          cwd: root, stdin: StringIO.new(valid_report)
        )

        exit_code, stdout, _stderr = run(
          ['step', 'report', '--task-id', 'TASK-6', '--step-id', 'plan', '--read', '--root', root.to_s],
          cwd: root
        )
        expect(exit_code).to eq(0)
        expect(stdout).to include('## Result')
      end
    end

    it 'appends a trailing newline if the body lacks one' do
      with_tmp_project do |root|
        init_project(root)
        path = root + '.owl/local/reports/TASK-7/plan.md'
        path.dirname.mkpath
        path.write('no trailing newline')
        exit_code, stdout, _stderr = run(
          ['step', 'report', '--task-id', 'TASK-7', '--step-id', 'plan', '--read', '--root', root.to_s],
          cwd: root
        )
        expect(exit_code).to eq(0)
        expect(stdout).to end_with("\n")
      end
    end

    it 'reports report_not_found with exit 1 when no report exists' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(
          ['step', 'report', '--task-id', 'TASK-9', '--step-id', 'plan', '--read', '--root', root.to_s],
          cwd: root
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('report_not_found')
      end
    end
  end

  describe '--schema flag' do
    it 'prints the public step_report JSON Schema and exits 0' do
      exit_code, stdout, _stderr = run(['step', 'report', '--schema'], cwd: Pathname.new(Dir.pwd))
      expect(exit_code).to eq(0)
      parsed = JSON.parse(stdout)
      expect(parsed['$schema']).to eq('https://json-schema.org/draft/2020-12/schema')
      expect(parsed['$id']).to eq('https://owl.dev/schemas/step_report/v1.json')
      expect(parsed['required']).to eq(%w[status summary])
      expect(parsed.dig('properties', 'status', 'enum')).to include('returned_normally', 'error')
      expect(parsed['x-required-sections']).to eq(['Result'])
    end

    it 'does not require --task-id / --step-id' do
      exit_code, _stdout, stderr = run(['step', 'report', '--schema'], cwd: Pathname.new(Dir.pwd))
      expect(exit_code).to eq(0)
      expect(stderr).to be_empty
    end
  end

  describe 'session_type lock enforcement (RFC #1 §2)' do
    let(:execution_report) do
      <<~MD
        ---
        status: returned_normally
        summary: "Done."
        session_type: execution
        ---

        ## Result

        x.
      MD
    end

    let(:discussion_report) do
      <<~MD
        ---
        status: returned_normally
        summary: "Done."
        session_type: discussion
        ---

        ## Result

        x.
      MD
    end

    it 'allows the write when no active-step lock exists (backward compat)' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, _stderr = run(
          ['step', 'report', '--task-id', 'TASK-NL', '--step-id', 'plan',
           '--body', '-', '--root', root.to_s],
          cwd: root, stdin: StringIO.new(execution_report)
        )
        expect(exit_code).to eq(0)
      end
    end

    it 'rejects with exit 2 when the report session_type does not match the lock' do
      with_tmp_project do |root|
        init_project(root)
        Owl::Steps::Internal::ActiveStepLock.write(
          root: root, task_id: 'TASK-MM', step_id: 'plan', session_type: 'execution'
        )
        exit_code, _stdout, stderr = run(
          ['step', 'report', '--task-id', 'TASK-MM', '--step-id', 'plan',
           '--body', '-', '--root', root.to_s],
          cwd: root, stdin: StringIO.new(discussion_report)
        )
        expect(exit_code).to eq(2)
        payload = JSON.parse(stderr)
        expect(payload.dig('error', 'code')).to eq('session_type_mismatch')
        expect(payload.dig('error', 'details', 'locked_session_type')).to eq('execution')
        expect(payload.dig('error', 'details', 'report_session_type')).to eq('discussion')
      end
    end

    it 'allows the write when session_type matches the lock' do
      with_tmp_project do |root|
        init_project(root)
        Owl::Steps::Internal::ActiveStepLock.write(
          root: root, task_id: 'TASK-OK', step_id: 'plan', session_type: 'execution'
        )
        exit_code, _stdout, _stderr = run(
          ['step', 'report', '--task-id', 'TASK-OK', '--step-id', 'plan',
           '--body', '-', '--root', root.to_s],
          cwd: root, stdin: StringIO.new(execution_report)
        )
        expect(exit_code).to eq(0)
      end
    end
  end

  describe '--template flag' do
    it 'prints a markdown skeleton and exits 0' do
      exit_code, stdout, _stderr = run(['step', 'report', '--template'], cwd: Pathname.new(Dir.pwd))
      expect(exit_code).to eq(0)
      expect(stdout).to start_with("---\n")
      expect(stdout).to include('status: returned_normally')
      expect(stdout).to include('summary: "<one-line>"')
      expect(stdout).to include('session_type: execution')
      expect(stdout).to include("\n## Result\n")
    end

    it 'produces a body that validates against the default output_spec' do
      _, stdout, = run(['step', 'report', '--template'], cwd: Pathname.new(Dir.pwd))
      result = Owl::Subagents::Internal::OutputSpec.validate(stdout)
      expect(result).to be_ok
    end
  end
end
