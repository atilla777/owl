# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'

require 'owl/cli/api'
require 'owl/specs/internal/task_merger'

RSpec.describe Owl::Specs::Internal::TaskMerger do
  def run_cli(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    stdout.string
  end

  def init_project(root)
    run_cli(['init', '--root', root.to_s], cwd: root)
  end

  def create_task(root)
    payload = JSON.parse(run_cli(['task', 'create', '--workflow', 'feature', '--title', 't', '--json'], cwd: root))
    payload.dig('task', 'id')
  end

  def seed_spec(root)
    write("#{root}/specs/billing/spec.md", <<~MD)
      ---
      status: active
      summary: Billing.
      ---

      # Spec

      ## Purpose

      Billing behaviour.

      ## Requirements

      ### Requirement: Invoices
      The system SHALL issue invoices.

      #### Scenario: Issue
      - WHEN a sale completes
      - THEN an invoice is issued
      - TEST: specs/billing/spec.md
    MD
  end

  it 'skips with no_spec_delta when the file is absent' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root)
      task_id = create_task(root)

      result = described_class.merge(root: root, task_id: task_id)

      expect(result).to be_ok
      expect(result.value).to include(applied: false, reason: 'no_spec_delta')
    end
  end

  it 'propagates a real resolve error (task_not_found) rather than skipping' do
    with_tmp_project do |root|
      init_project(root)

      result = described_class.merge(root: root, task_id: 'TASK-9999')

      expect(result).to be_err
      expect(result.code).to eq(:task_not_found)
    end
  end

  it 'applies a traced delta and reports an ok trace gate' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root)
      task_id = create_task(root)
      write("#{root}/tasks/#{task_id}/spec_delta.md", <<~MD)
        ---
        domain: billing
        status: draft
        ---

        ## ADDED Requirements

        ### Requirement: Late fees
        The system SHALL charge late fees.

        #### Scenario: Late
        - WHEN payment is late
        - THEN a fee is added
        - TEST: specs/billing/spec.md
      MD

      result = described_class.merge(root: root, task_id: task_id)

      expect(result).to be_ok
      expect(result.value[:ok]).to be(true)
      expect(result.value[:domain]).to eq('billing')
    end
  end
end
