# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'

require 'owl/cli/api'

# Backward-compat guard for the spec-layer wiring (TASK-0007): the `feature`
# workflow's merge_docs step now runs `owl spec merge` in addition to
# `owl publish`. A task that declares NO `spec_delta` must see ZERO behavioural
# change — both commands must be clean no-ops that write nothing under specs/.
RSpec.describe 'merge_docs spec merge backward compatibility' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def init_project(root)
    run(['init', '--root', root.to_s], cwd: root)
  end

  def create_task(root)
    _, stdout, = run(['task', 'create', '--workflow', 'feature', '--title', 'spec-less', '--json'], cwd: root)
    JSON.parse(stdout).dig('task', 'id')
  end

  it 'is a clean no-op for a task with no spec_delta (writes nothing under specs/)' do
    with_tmp_project do |root|
      init_project(root)
      task_id = create_task(root)

      exit_code, stdout, = run(['spec', 'merge', task_id, '--root', root.to_s, '--json'], cwd: root)

      expect(exit_code).to eq(0)
      body = JSON.parse(stdout)
      expect(body).to include('ok' => true, 'applied' => false, 'reason' => 'no_spec_delta')
      expect(Pathname.new("#{root}/specs").exist?).to be(false)
    end
  end

  it 'keeps the existing publish no-op path (no_publishable_step) alongside the spec merge no-op' do
    with_tmp_project do |root|
      init_project(root)
      task_id = create_task(root)

      _publish_exit, _pub_out, pub_err = run(['publish', task_id, '--root', root.to_s, '--json'], cwd: root)
      merge_exit, merge_out, = run(['spec', 'merge', task_id, '--root', root.to_s, '--json'], cwd: root)

      # publish is a benign no-op (no `publish` step / nothing to publish) ...
      expect(JSON.parse(pub_err).dig('error', 'code')).to eq('no_publishable_step')
      # ... and spec merge is a benign no-op (no spec_delta declared/written).
      expect(merge_exit).to eq(0)
      expect(JSON.parse(merge_out)).to include('ok' => true, 'reason' => 'no_spec_delta')
      expect(Pathname.new("#{root}/specs").exist?).to be(false)
    end
  end

  it 'instructs the executor to run both owl publish and owl spec merge' do
    with_tmp_project do |root|
      init_project(root)
      context = Pathname.new("#{root}/.owl/workflows/feature/merge_docs.context.md").read
      expect(context).to include('owl publish TASK-ID')
      expect(context).to include('owl spec merge TASK-ID')
    end
  end
end
