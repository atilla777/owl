# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'pathname'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'owl workflow validate · step_context_frontmatter mapping (KOS-156)' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  it 'returns exit 4 and error_class: step_context_frontmatter ' \
     'for a step whose .context.md frontmatter violates the contract ' \
     '(drift_policy: block surfaces the warning as an error)' do
    with_tmp_project do |root|
      run(['init', '--root', root.to_s], cwd: root)

      workflow_dir = root.join('.owl', 'workflows', 'fm_broken')
      FileUtils.mkdir_p(workflow_dir)
      workflow_path = workflow_dir.join('workflow.yaml')
      workflow_path.write(<<~YAML)
        id: fm_broken
        kind: task
        title: Frontmatter contract smoke test
        artifacts:
          out:
            type: brief
            storage:
              role: tasks
              path: "{{task.id}}/out.md"
        steps:
          - id: only
            skill: owl-step-discussion
            session_type: discussion
            tier: standard
            drift_policy: block
            context_file: only.context.md
            creates: [out]
      YAML
      workflow_dir.join('only.context.md').write(<<~MD)
        ---
        step_id: completely_wrong_id
        ---

        body
      MD

      # Register fm_broken in the project registry; the seeded registry has only
      # the standard workflows. We can either go by path or by id; --path works.
      exit_code, _stdout, stderr = run(
        ['workflow', 'validate', workflow_path.to_s, '--root', root.to_s, '--json'],
        cwd: root
      )

      expect(exit_code).to eq(4)
      payload = JSON.parse(stderr)
      expect(payload.dig('error', 'error_class')).to eq('step_context_frontmatter')
      codes = payload.dig('error', 'details', 'errors').map { |e| e['code'] }
      expect(codes).to include('step_context_frontmatter_step_id_mismatch')
    end
  end

  it 'returns exit 0 with valid: true when the same step has a frontmatter that matches' do
    with_tmp_project do |root|
      run(['init', '--root', root.to_s], cwd: root)

      workflow_dir = root.join('.owl', 'workflows', 'fm_ok')
      FileUtils.mkdir_p(workflow_dir)
      workflow_path = workflow_dir.join('workflow.yaml')
      workflow_path.write(<<~YAML)
        id: fm_ok
        kind: task
        title: Frontmatter OK
        artifacts:
          out:
            type: brief
            storage:
              role: tasks
              path: "{{task.id}}/out.md"
        steps:
          - id: only
            skill: owl-step-discussion
            session_type: discussion
            tier: standard
            drift_policy: block
            context_file: only.context.md
            creates: [out]
      YAML
      workflow_dir.join('only.context.md').write(<<~MD)
        ---
        step_id: only
        applies_to_session_type: discussion
        intended_audience: orchestrator
        ---

        body
      MD

      exit_code, stdout, = run(
        ['workflow', 'validate', workflow_path.to_s, '--root', root.to_s, '--json'],
        cwd: root
      )

      expect(exit_code).to eq(0)
      expect(JSON.parse(stdout)['valid']).to be(true)
    end
  end
end
