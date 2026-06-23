# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'

require 'owl/cli/api'
require 'owl/commit_push/api'
require 'owl/result'

RSpec.describe 'owl commit-push CLI' do
  def run(argv)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: '/tmp')
    [exit_code, stdout.string, stderr.string]
  end

  it 'emits {ok:true, task_id, commit_sha, pushed} on success' do
    allow(Owl::CommitPush::Api).to receive(:commit_push)
      .and_return(Owl::Result.ok(task_id: 'TASK-0001', commit_sha: 'abc123', pushed: true))

    exit_code, stdout, = run(['commit-push', 'TASK-0001', '--message', 'Owl: deliver', '--root', '/repo'])
    body = JSON.parse(stdout)

    expect(exit_code).to eq(0)
    expect(body).to eq('ok' => true, 'task_id' => 'TASK-0001', 'commit_sha' => 'abc123', 'pushed' => true)
    expect(Owl::CommitPush::Api).to have_received(:commit_push)
      .with(root: Pathname.new('/repo'), task_id: 'TASK-0001', message: 'Owl: deliver')
  end

  it 'requires --message' do
    exit_code, _, stderr = run(['commit-push', 'TASK-0001', '--root', '/repo'])
    body = JSON.parse(stderr)

    expect(exit_code).to eq(1)
    expect(body['ok']).to be(false)
    expect(body.dig('error', 'code')).to eq('invalid_arguments')
  end

  it 'requires a TASK-ID' do
    exit_code, _, stderr = run(['commit-push', '--message', 'Owl: x', '--root', '/repo'])
    body = JSON.parse(stderr)

    expect(exit_code).to eq(1)
    expect(body.dig('error', 'code')).to eq('invalid_arguments')
  end

  it 'propagates a recoverable push_retryable error to stderr with exit 2' do
    allow(Owl::CommitPush::Api).to receive(:commit_push).and_return(
      Owl::Result.err(code: :push_retryable, message: 'push failed',
                      details: { commit_sha: 'abc123' }, error_class: :recoverable)
    )

    exit_code, _, stderr = run(['commit-push', 'TASK-0001', '--message', 'Owl: x', '--root', '/repo'])
    body = JSON.parse(stderr)

    expect(exit_code).to eq(2)
    expect(body['ok']).to be(false)
    expect(body.dig('error', 'code')).to eq('push_retryable')
    expect(body.dig('error', 'details', 'commit_sha')).to eq('abc123')
  end
end
