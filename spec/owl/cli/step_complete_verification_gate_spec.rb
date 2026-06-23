# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

# End-to-end gate behaviour through the real `owl` CLI on the seeded feature
# workflow: `review_code` carries `verify: true`. Uses the real shell builtins
# `true`/`false` as verification commands so the objective run is real but
# instant.
RSpec.describe 'review_code objective verification gate (owl CLI)' do
  def cli(argv, root)
    out = StringIO.new
    err = StringIO.new
    code = Owl::Cli::Api.run(argv: argv, stdout: out, stderr: err, env: {}, cwd: root.to_s)
    [code, out.string, err.string]
  end

  def set_command(root, command)
    cli(['config', 'set', 'settings.verification.command', command, '--root', root.to_s, '--json'], root)
  end

  def write_doc(root, task_id, filename, body)
    path = root + "tasks/#{task_id}/#{filename}"
    path.dirname.mkpath
    path.write(body)
  end

  def complete(root, task_id, step_id)
    cli(['step', 'complete', task_id, step_id, '--root', root.to_s, '--json'], root)
  end

  def ready_ids(root, task_id)
    _, out, = cli(['task', 'ready-steps', task_id, '--root', root.to_s, '--json'], root)
    JSON.parse(out)['ready'].map { |s| s['id'] }
  end

  # Drive a fresh feature task up to a running `review_code` with review.md
  # written, leaving the verification command unset.
  def drive_to_review_code(root)
    cli(['init', '--root', root.to_s], root)
    _, out, = cli(['task', 'create', '--workflow', 'feature', '--title', 'gate', '--root', root.to_s, '--json'], root)
    task_id = JSON.parse(out).dig('task', 'id')

    step('brief', root, task_id, 'brief.md', brief_doc, variant: 'feature')
    step('design', root, task_id, 'design.md', design_doc)
    step('plan', root, task_id, 'plan.md', plan_doc)
    step('implement', root, task_id, nil, nil)

    cli(['step', 'start', task_id, 'review_code', '--root', root.to_s, '--json'], root)
    write_doc(root, task_id, 'review.md', review_doc)
    task_id
  end

  def step(step_id, root, task_id, filename, body, variant: nil)
    argv = ['step', 'start', task_id, step_id, '--root', root.to_s, '--json']
    argv += ['--variant', variant] if variant
    cli(argv, root)
    write_doc(root, task_id, filename, body) if filename
    complete(root, task_id, step_id)
  end

  def brief_doc
    <<~MD
      ---
      status: approved
      summary: gate
      ---

      # Brief

      ## Problem

      p

      ## Goal

      g

      ## Scenarios

      ### Requirement: Gate

      The system SHALL gate.

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
      summary: gate
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
      summary: gate
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

  def verification_doc
    <<~MD
      ---
      status: passed
      summary: self report
      ---

      # Verification

      ## Summary

      s

      ## Commands

      - manual

      ## Outcomes

      - green
    MD
  end

  it 'blocks completion when the configured command fails (merge_docs stays not-ready)' do
    with_tmp_project do |root|
      task_id = drive_to_review_code(root)
      set_command(root, 'sh -c "exit 1"')

      code, _out, err = complete(root, task_id, 'review_code')
      expect(code).not_to eq(0)
      expect(JSON.parse(err).dig('error', 'code')).to eq('verification_failed')
      expect(ready_ids(root, task_id)).not_to include('merge_docs')

      # Owl authored the objective failed status into verification.md.
      expect((root + "tasks/#{task_id}/verification.md").read).to match(/^status: failed$/)
    end
  end

  it 'allows completion when the configured command passes (merge_docs becomes ready)' do
    with_tmp_project do |root|
      task_id = drive_to_review_code(root)
      set_command(root, 'sh -c "exit 0"')

      code, out, = complete(root, task_id, 'review_code')
      expect(code).to eq(0), "out=#{out}"
      expect(JSON.parse(out).dig('step', 'status')).to eq('done')
      expect(ready_ids(root, task_id)).to include('merge_docs')
      expect((root + "tasks/#{task_id}/verification.md").read).to match(/^status: passed$/)
    end
  end

  it 'is fail-open with a warning when no command is configured' do
    with_tmp_project do |root|
      task_id = drive_to_review_code(root)
      # No command set; the agent authors verification.md as a self-report.
      write_doc(root, task_id, 'verification.md', verification_doc)

      code, out, err = complete(root, task_id, 'review_code')
      expect(code).to eq(0), "out=#{out} err=#{err}"
      expect(err).to include('verification_gate_inactive')
      expect(ready_ids(root, task_id)).to include('merge_docs')
    end
  end
end
