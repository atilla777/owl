# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

# The additive `task_status` field on `owl step complete` JSON: present (with
# the terminal status) only when completing the step finalized the task; absent
# while the task is still in progress.
RSpec.describe 'owl step complete task_status field' do
  def cli(argv, root)
    out = StringIO.new
    err = StringIO.new
    code = Owl::Cli::Api.run(argv: argv, stdout: out, stderr: err, env: {}, cwd: root.to_s)
    [code, out.string, err.string]
  end

  def setup_two_step_project(root)
    cli(['init', '--root', root.to_s], root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        quick:
          enabled: true
          source: "workflows/quick/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/quick/workflow.yaml", <<~YAML)
      id: quick
      kind: task
      steps:
        - id: a
        - id: b
          requires: ["a"]
      artifacts: []
    YAML
    cli(['task', 'create', '--workflow', 'quick', '--title', 't', '--root', root.to_s, '--json'], root)
    'TASK-0001'
  end

  def complete(root, task_id, step_id)
    cli(['step', 'start', task_id, step_id, '--root', root.to_s, '--json'], root)
    cli(['step', 'complete', task_id, step_id, '--root', root.to_s, '--json'], root)
  end

  it 'omits task_status for a non-final step and includes it on the final step' do
    with_tmp_project do |root|
      task_id = setup_two_step_project(root)

      _, out_a, = complete(root, task_id, 'a')
      expect(JSON.parse(out_a)).not_to have_key('task_status')

      code, out_b, err = complete(root, task_id, 'b')
      expect(code).to eq(0), "out=#{out_b} err=#{err}"
      expect(JSON.parse(out_b)['task_status']).to eq('done')
    end
  end
end
