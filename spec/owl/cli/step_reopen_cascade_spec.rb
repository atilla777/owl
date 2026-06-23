# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

# A failed objective verification at `review_code` is recovered with the
# existing reopen machinery: reset the still-running review step, then
# `owl step reopen implement --cascade` sends the build step (and its
# transitive dependents) back to pending so the implement → review cycle
# repeats.
RSpec.describe 'reopen cascade after a failed verification (owl CLI)' do
  def cli(argv, root)
    out = StringIO.new
    err = StringIO.new
    code = Owl::Cli::Api.run(argv: argv, stdout: out, stderr: err, env: {}, cwd: root.to_s)
    [code, out.string, err.string]
  end

  def write_doc(root, task_id, filename, body)
    path = root + "tasks/#{task_id}/#{filename}"
    path.dirname.mkpath
    path.write(body)
  end

  def step_status(root, task_id, step_id)
    _, out, = cli(['status', task_id, '--root', root.to_s, '--json'], root)
    JSON.parse(out)['steps'].find { |s| s['id'] == step_id }['status']
  end

  def step(step_id, root, task_id, filename, body, variant: nil)
    argv = ['step', 'start', task_id, step_id, '--root', root.to_s, '--json']
    argv += ['--variant', variant] if variant
    cli(argv, root)
    write_doc(root, task_id, filename, body) if filename
    cli(['step', 'complete', task_id, step_id, '--root', root.to_s, '--json'], root)
  end

  def drive_to_failed_review(root)
    cli(['init', '--root', root.to_s], root)
    _, out, = cli(['task', 'create', '--workflow', 'feature', '--title', 'reopen', '--root', root.to_s, '--json'], root)
    task_id = JSON.parse(out).dig('task', 'id')

    step('brief', root, task_id, 'brief.md', brief_doc, variant: 'feature')
    step('design', root, task_id, 'design.md', design_doc)
    step('plan', root, task_id, 'plan.md', plan_doc)
    step('implement', root, task_id, nil, nil)

    cli(['config', 'set', 'settings.verification.command', 'sh -c "exit 1"', '--root', root.to_s, '--json'], root)
    cli(['step', 'start', task_id, 'review_code', '--root', root.to_s, '--json'], root)
    write_doc(root, task_id, 'review.md', review_doc)
    # Failing gate: review_code stays running, verification.md authored as failed.
    cli(['step', 'complete', task_id, 'review_code', '--root', root.to_s, '--json'], root)
    task_id
  end

  it 'sends implement (and the running review step) back to pending' do
    with_tmp_project do |root|
      task_id = drive_to_failed_review(root)
      expect(step_status(root, task_id, 'review_code')).to eq('running')
      expect(step_status(root, task_id, 'implement')).to eq('done')

      # Reset the running review step, then cascade-reopen the build step.
      cli(['step', 'reset', task_id, 'review_code', '--root', root.to_s, '--json'], root)
      code, out, = cli(['step', 'reopen', task_id, 'implement', '--cascade', '--root', root.to_s, '--json'], root)
      expect(code).to eq(0), "out=#{out}"
      expect(JSON.parse(out)['reopened']).to include('implement')

      expect(step_status(root, task_id, 'implement')).to eq('pending')
      expect(step_status(root, task_id, 'review_code')).to eq('pending')

      # The implement → review cycle can now repeat.
      _, ready, = cli(['task', 'ready-steps', task_id, '--root', root.to_s, '--json'], root)
      expect(JSON.parse(ready)['ready'].map { |s| s['id'] }).to include('implement')
    end
  end

  def brief_doc
    <<~MD
      ---
      status: approved
      summary: reopen
      ---

      # Brief

      ## Problem

      p

      ## Goal

      g

      ## Scenarios

      ### Requirement: Reopen

      The system SHALL reopen.

      #### Scenario: Happy
      - WHEN x
      - THEN y

      ## Edge cases

      - none

      ## Acceptance criteria

      - done
    MD
  end

  def design_doc
    <<~MD
      ---
      status: draft
      summary: reopen
      ---

      # Design

      ## Context

      c

      ## Decision

      d

      ## Alternatives

      - none

      ## Risks

      - none

      ## API

      - n/a
    MD
  end

  def plan_doc
    <<~MD
      # Plan

      ## Goal

      g

      ## Checklist

      - do it

      ## Smoke test

      run
    MD
  end

  def review_doc
    <<~MD
      ---
      status: resolved
      summary: reopen
      ---

      # Review

      ## Summary

      s

      ## Findings

      - none

      ## Resolution

      - n/a
    MD
  end
end
