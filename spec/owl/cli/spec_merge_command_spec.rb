# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'owl spec merge CLI' do
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
    _, stdout, = run(['task', 'create', '--workflow', 'feature', '--title', 'm', '--json'], cwd: root)
    JSON.parse(stdout).dig('task', 'id')
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

  def write_delta(root, task_id, body)
    write("#{root}/tasks/#{task_id}/spec_delta.md", body)
  end

  def traced_delta
    <<~MD
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
  end

  it 'requires the TASK-ID positional argument' do
    with_tmp_project do |root|
      init_project(root)
      exit_code, _stdout, stderr = run(['spec', 'merge', '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).not_to eq(0)
      expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
    end
  end

  it 'returns a no-op for a task with no spec_delta (exit 0)' do
    with_tmp_project do |root|
      init_project(root)
      task_id = create_task(root)
      exit_code, stdout, = run(['spec', 'merge', task_id, '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      body = JSON.parse(stdout)
      expect(body['ok']).to be(true)
      expect(body['applied']).to be(false)
      expect(body['reason']).to eq('no_spec_delta')
    end
  end

  it 'applies a traced delta and exits 0' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root)
      task_id = create_task(root)
      write_delta(root, task_id, traced_delta)
      exit_code, stdout, = run(['spec', 'merge', task_id, '--root', root.to_s, '--json'], cwd: root)
      expect(exit_code).to eq(0)
      body = JSON.parse(stdout)
      expect(body['ok']).to be(true)
      expect(body['applied']).to be(true)
      expect(body['unchanged']).to eq('added' => 0, 'modified' => 0, 'removed' => 0)
      expect(body['domain']).to eq('billing')
    end
  end

  it 'previews under --dry-run without writing the spec' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root)
      task_id = create_task(root)
      write_delta(root, task_id, traced_delta)
      before = Pathname.new("#{root}/specs/billing/spec.md").read

      exit_code, stdout, = run(['spec', 'merge', task_id, '--root', root.to_s, '--dry-run', '--json'], cwd: root)

      expect(exit_code).to eq(0)
      expect(JSON.parse(stdout)['applied']).to be(false)
      expect(Pathname.new("#{root}/specs/billing/spec.md").read).to eq(before)
    end
  end

  it 'exits 1 when the trace gate fails on an untraced merged scenario' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root)
      task_id = create_task(root)
      write_delta(root, task_id, <<~MD)
        ---
        domain: billing
        status: draft
        ---

        ## ADDED Requirements

        ### Requirement: Refunds
        The system SHALL issue refunds.

        #### Scenario: No test
        - WHEN a refund is requested
        - THEN money is returned
      MD

      exit_code, stdout, = run(['spec', 'merge', task_id, '--root', root.to_s, '--json'], cwd: root)

      expect(exit_code).to eq(1)
      body = JSON.parse(stdout)
      expect(body['ok']).to be(false)
      expect(body['applied']).to be(true)
    end
  end

  it 'surfaces a missing-domain delta as a structured error' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root)
      task_id = create_task(root)
      write_delta(root, task_id, "## ADDED Requirements\n\n### Requirement: X\nThe system SHALL X.\n")

      exit_code, _stdout, stderr = run(['spec', 'merge', task_id, '--root', root.to_s, '--json'], cwd: root)

      expect(exit_code).not_to eq(0)
      expect(JSON.parse(stderr).dig('error', 'code')).to eq('spec_delta_missing_domain')
    end
  end

  it 'prints a readable no-op summary under --no-json' do
    with_tmp_project do |root|
      init_project(root)
      task_id = create_task(root)
      exit_code, stdout, = run(['spec', 'merge', task_id, '--root', root.to_s, '--no-json'], cwd: root)
      expect(exit_code).to eq(0)
      expect(stdout).to include('no spec_delta artifact')
    end
  end

  it 'prints a readable apply+trace summary under --no-json' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root)
      task_id = create_task(root)
      write_delta(root, task_id, traced_delta)
      exit_code, stdout, = run(['spec', 'merge', task_id, '--root', root.to_s, '--no-json'], cwd: root)
      expect(exit_code).to eq(0)
      expect(stdout).to include('spec merge billing')
      expect(stdout).to include('delta: added 1')
      expect(stdout).to include('unchanged: added 0  modified 0  removed 0')
      expect(stdout).to include('trace: valid=true')
    end
  end
end
