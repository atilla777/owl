# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

# The seeded `brief` artifact declares `validation.completion_front_matter:
# { status: approved }`. That requirement is enforced ONLY at `owl step
# complete` (via OutputValidator), not by plain well-formedness validation:
# a draft brief is a valid document but cannot complete the brief step until
# it records explicit approval. Drives the REAL seeded config end-to-end.
RSpec.describe 'brief step completion gate (approved required)' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def setup_task(root)
    run(['init', '--root', root.to_s], cwd: root)
    _, stdout, = run(['task', 'create', '--workflow', 'feature', '--title', 't',
                      '--root', root.to_s, '--json'], cwd: root)
    JSON.parse(stdout).dig('task', 'id')
  end

  def brief_body(status)
    <<~MD
      ---
      status: #{status}
      summary: gate test
      ---

      # Brief

      ## Problem

      p

      ## Goal

      g

      ## Scenarios

      ### Requirement: Well formed

      The system SHALL do the thing.

      #### Scenario: Happy path
      - WHEN something happens
      - THEN the expected outcome is observed

      ## Edge cases

      - none

      ## Acceptance criteria

      - [ ] done
    MD
  end

  it 'blocks `step complete` while the (well-formed) brief is still draft' do
    with_tmp_project do |root|
      task_id = setup_task(root)
      run(['step', 'start', task_id, 'brief', '--variant', 'feature', '--root', root.to_s], cwd: root)
      write("#{root}/tasks/#{task_id}/brief.md", brief_body('draft'))

      # The draft brief is well-formed (plain validate passes) ...
      validate = run(['artifact', 'validate', task_id, 'brief', '--root', root.to_s, '--json'], cwd: root)
      expect(JSON.parse(validate[1])['valid']).to be(true)

      # ... but completing the step is blocked by the approval gate.
      exit_code, _stdout, stderr = run(['step', 'complete', task_id, 'brief', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).not_to eq(0)
      error = JSON.parse(stderr)['error']
      expect(error['code']).to eq('step_outputs_invalid')
      types = error.dig('details', 'results').flat_map { |r| r['violations'].map { |v| v['type'] } }
      expect(types).to include('completion_requirement')
    end
  end

  it 'allows `step complete` once the brief is approved' do
    with_tmp_project do |root|
      task_id = setup_task(root)
      run(['step', 'start', task_id, 'brief', '--variant', 'feature', '--root', root.to_s], cwd: root)
      write("#{root}/tasks/#{task_id}/brief.md", brief_body('approved'))

      exit_code, stdout, = run(['step', 'complete', task_id, 'brief', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0), "stdout=#{stdout}"
      expect(JSON.parse(stdout)['ok']).to be(true)
    end
  end
end
