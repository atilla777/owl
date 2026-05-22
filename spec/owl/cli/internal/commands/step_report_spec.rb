# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

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

    it 'rejects missing --task-id with invalid_arguments' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(
          ['step', 'report', '--step-id', 'plan', '--body', '-', '--root', root.to_s],
          cwd: root, stdin: StringIO.new(valid_report)
        )
        expect(exit_code).to eq(1)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
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
end
