# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'

require 'owl/cli/api'
require 'owl/specs/api'

RSpec.describe 'Owl::Specs::Api.merge_task' do
  def run_cli(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [stdout.string, stderr.string]
  end

  def init_project(root)
    run_cli(['init', '--root', root.to_s], cwd: root)
  end

  def create_task(root)
    stdout, = run_cli(['task', 'create', '--workflow', 'feature', '--title', 'merge', '--json'], cwd: root)
    JSON.parse(stdout).dig('task', 'id')
  end

  def seed_spec(root, domain = 'billing')
    write("#{root}/specs/#{domain}/spec.md", <<~MD)
      ---
      status: active
      summary: Billing rules.
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

  def untraced_delta
    <<~MD
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
  end

  it 'applies a present, traced delta and passes the trace gate' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root)
      task_id = create_task(root)
      write_delta(root, task_id, traced_delta)

      result = Owl::Specs::Api.merge_task(root: root, task_id: task_id)

      expect(result).to be_ok
      expect(result.value[:ok]).to be(true)
      expect(result.value[:applied]).to be(true)
      expect(result.value[:domain]).to eq('billing')
      expect(result.value[:merge][:applied]).to eq(added: 1, modified: 0, removed: 0)
      expect(result.value[:trace][:valid]).to be(true)
      expect(Pathname.new("#{root}/specs/billing/spec.md").read).to include('### Requirement: Late fees')
    end
  end

  it 'fails the gate when the merged spec has an untraced scenario but leaves the delta applied' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root)
      task_id = create_task(root)
      write_delta(root, task_id, untraced_delta)

      result = Owl::Specs::Api.merge_task(root: root, task_id: task_id)

      expect(result).to be_ok
      expect(result.value[:ok]).to be(false)
      expect(result.value[:applied]).to be(true)
      expect(result.value[:trace][:untraced]).to include(hash_including(scenario: 'No test'))
      expect(Pathname.new("#{root}/specs/billing/spec.md").read).to include('### Requirement: Refunds')
    end
  end

  it 'returns a graceful skip when the task declares no spec_delta' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root)
      task_id = create_task(root)

      result = Owl::Specs::Api.merge_task(root: root, task_id: task_id)

      expect(result).to be_ok
      expect(result.value[:ok]).to be(true)
      expect(result.value[:applied]).to be(false)
      expect(result.value[:reason]).to eq('no_spec_delta')
    end
  end

  it 'previews under dry_run without writing the spec' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root)
      task_id = create_task(root)
      write_delta(root, task_id, traced_delta)
      before = Pathname.new("#{root}/specs/billing/spec.md").read

      result = Owl::Specs::Api.merge_task(root: root, task_id: task_id, dry_run: true)

      expect(result).to be_ok
      expect(result.value[:applied]).to be(false)
      expect(result.value[:merge][:dry_run]).to be(true)
      expect(Pathname.new("#{root}/specs/billing/spec.md").read).to eq(before)
    end
  end

  it 'errors with spec_delta_missing_domain when the delta omits domain front matter' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root)
      task_id = create_task(root)
      write_delta(root, task_id, "## ADDED Requirements\n\n### Requirement: X\nThe system SHALL X.\n")

      result = Owl::Specs::Api.merge_task(root: root, task_id: task_id)

      expect(result).to be_err
      expect(result.code).to eq(:spec_delta_missing_domain)
    end
  end

  it 'rejects an unsafe domain slug with invalid_domain' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root)
      task_id = create_task(root)
      write_delta(root, task_id, "---\ndomain: \"../evil\"\nstatus: draft\n---\n\n## ADDED Requirements\n\n" \
                                 "### Requirement: X\nThe system SHALL X.\n")

      result = Owl::Specs::Api.merge_task(root: root, task_id: task_id)

      expect(result).to be_err
      expect(result.code).to eq(:invalid_domain)
    end
  end

  it 'propagates a P4 delta error (delta_conflict) and writes nothing' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root)
      task_id = create_task(root)
      conflicting = <<~MD
        ---
        domain: billing
        status: draft
        ---

        ## ADDED Requirements

        ### Requirement: Invoices

        The system SHALL issue invoices.

        #### Scenario: Dup
        - WHEN a sale completes
        - THEN an invoice is issued
        - TEST: specs/billing/spec.md
      MD
      write_delta(root, task_id, conflicting)
      before = Pathname.new("#{root}/specs/billing/spec.md").read

      result = Owl::Specs::Api.merge_task(root: root, task_id: task_id)

      expect(result).to be_err
      expect(result.code).to eq(:delta_conflict)
      expect(Pathname.new("#{root}/specs/billing/spec.md").read).to eq(before)
    end
  end
end
