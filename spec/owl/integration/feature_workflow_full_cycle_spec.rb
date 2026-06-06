# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'stringio'

require 'owl/cli/api'

# End-to-end happy-path для seeded feature workflow: проходит весь цикл
# `owl init → task create → (для каждого шага: ready-steps → step start →
# write artifact if creates → step complete) → task inspect`. SoT-инвариант
# «оркестратор → CLI → артефакты → archive» smoke-тестируется в одном
# прогоне поверх реальных filesystem backends, без моков, без реального
# subagent runtime, без git.
module FeatureWorkflowFullCycleFixtures
  FEATURE_STEPS = %w[brief design plan implement review_code merge_docs archive commit_push].freeze

  # filename within tasks/<TASK> for each step that has `creates:` in seeded YAML.
  STEPS_WITH_ARTIFACTS = {
    'brief' => 'brief.md',
    'design' => 'design.md',
    'plan' => 'plan.md',
    'implement' => 'verification.md',
    'review_code' => 'review.md'
  }.freeze

  module_function

  def minimal_artifact(step_id, task_id)
    case step_id
    when 'brief'       then brief_artifact(task_id)
    when 'design'      then design_artifact(task_id)
    when 'plan'        then plan_artifact
    when 'implement'   then verification_artifact(task_id)
    when 'review_code' then review_artifact(task_id)
    else raise "no minimal artifact for step #{step_id}"
    end
  end

  def brief_artifact(task_id)
    <<~MD
      ---
      status: draft
      summary: integration full-cycle #{task_id}
      ---

      # Brief

      ## Problem

      Integration test brief.

      ## Goal

      Verify CLI lifecycle.

      ## Scenarios

      ### Requirement: CLI lifecycle completes

      The system SHALL drive a feature task through every step via the CLI.

      #### Scenario: Happy path
      - WHEN each step is started and completed in order
      - THEN the task reaches commit_push without error

      ## Edge cases

      - none

      ## Acceptance criteria

      - smoke check passes
    MD
  end

  def design_artifact(task_id)
    <<~MD
      ---
      status: draft
      summary: integration full-cycle #{task_id}
      ---

      # Design

      ## Context

      Integration test.

      ## Decision

      Use seeded feature workflow.

      ## Alternatives

      - none

      ## Risks

      - none

      ## API

      - n/a
    MD
  end

  def plan_artifact
    <<~MD
      # Plan

      ## Goal

      Smoke.

      ## Checklist

      - run integration spec

      ## Smoke test

      bundle exec rspec spec/owl/integration/feature_workflow_full_cycle_spec.rb
    MD
  end

  def verification_artifact(task_id)
    <<~MD
      ---
      status: passed
      summary: integration full-cycle #{task_id}
      ---

      # Verification

      ## Summary

      Integration smoke verification.

      ## Commands

      - bundle exec rspec spec/owl/integration/feature_workflow_full_cycle_spec.rb

      ## Outcomes

      - green
    MD
  end

  def review_artifact(task_id)
    <<~MD
      ---
      status: resolved
      summary: integration full-cycle #{task_id}
      ---

      # Review

      ## Summary

      Integration self-review.

      ## Findings

      - none

      ## Resolution

      - n/a
    MD
  end
end

RSpec.describe 'seeded feature workflow happy-path full cycle (end-to-end)' do
  include FeatureWorkflowFullCycleFixtures

  def cli(argv, root)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def expect_ok(exit_code, stdout, stderr, label)
    expect(exit_code).to eq(0), "#{label} exited #{exit_code}; stderr=#{stderr.inspect}; stdout=#{stdout.inspect}"
  end

  def write_artifact(root, task_id, filename, body)
    path = root + "tasks/#{task_id}/#{filename}"
    FileUtils.mkdir_p(path.dirname.to_s)
    path.write(body)
  end

  it 'walks brief → design → plan → implement → review_code → merge_docs → archive → commit_push via owl CLI' do
    with_tmp_project do |root|
      ec, out, err = cli(%W[init --root #{root}], root)
      expect_ok(ec, out, err, 'owl init')
      expect((root + '.owl/workflows/feature/workflow.yaml').exist?).to be(true)

      ec, out, err = cli(
        %W[task create --workflow feature --title integration-full-cycle --root #{root} --json],
        root
      )
      expect_ok(ec, out, err, 'owl task create')
      task_id = JSON.parse(out).dig('task', 'id')
      expect(task_id).to be_a(String).and(match(/\ATASK-\d+\z/))

      FeatureWorkflowFullCycleFixtures::FEATURE_STEPS.each_with_index do |step_id, idx|
        ec, out, err = cli(%W[task ready-steps #{task_id} --root #{root} --json], root)
        expect_ok(ec, out, err, "task ready-steps before #{step_id}")
        ready_ids = JSON.parse(out)['ready'].map { |s| s['id'] }
        expect(ready_ids).to include(step_id),
                             "expected #{step_id} ready at idx=#{idx}, got #{ready_ids.inspect}"

        start_argv = %W[step start #{task_id} #{step_id} --root #{root} --json]
        start_argv += %w[--variant feature] if step_id == 'brief'
        ec, out, err = cli(start_argv, root)
        expect_ok(ec, out, err, "step start #{step_id}")
        expect(JSON.parse(out).dig('step', 'status')).to eq('running')

        if (artifact_path = FeatureWorkflowFullCycleFixtures::STEPS_WITH_ARTIFACTS[step_id])
          write_artifact(root, task_id, artifact_path, minimal_artifact(step_id, task_id))
        end

        ec, out, err = cli(%W[step complete #{task_id} #{step_id} --root #{root} --json], root)
        expect_ok(ec, out, err, "step complete #{step_id}")
        expect(JSON.parse(out).dig('step', 'status')).to eq('done')
      end

      ec, out, err = cli(%W[task ready-steps #{task_id} --root #{root} --json], root)
      expect_ok(ec, out, err, 'task ready-steps after commit_push')
      expect(JSON.parse(out)['ready']).to eq([])

      ec, out, err = cli(%W[task inspect #{task_id} --root #{root} --json], root)
      expect_ok(ec, out, err, 'task inspect (final)')
      steps = JSON.parse(out).dig('task', 'steps')
      expect(steps.map { |s| s['id'] }).to eq(FeatureWorkflowFullCycleFixtures::FEATURE_STEPS)
      statuses = steps.to_h { |s| [s['id'], s['status']] }
      FeatureWorkflowFullCycleFixtures::FEATURE_STEPS.each do |step_id|
        expect(statuses[step_id]).to eq('done'),
                                     "expected #{step_id} done, got #{statuses[step_id].inspect}"
      end
    end
  end
end
