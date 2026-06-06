# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'

require 'owl/cli/api'
require 'owl/specs/api'
require 'owl/validation/internal/front_matter_parser'

RSpec.describe 'Owl::Specs::Api.merge_task idempotency and dry-run preview' do
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
    JSON.parse(run_cli(['task', 'create', '--workflow', 'feature', '--title', 't', '--json'], cwd: root))
        .dig('task', 'id')
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

  def traced_delta(domain = 'billing')
    <<~MD
      ---
      domain: #{domain}
      status: draft
      ---

      ## ADDED Requirements

      ### Requirement: Late fees
      The system SHALL charge late fees.

      #### Scenario: Late
      - WHEN payment is late
      - THEN a fee is added
      - TEST: specs/#{domain}/spec.md
    MD
  end

  def write_delta(root, task_id, body)
    write("#{root}/tasks/#{task_id}/spec_delta.md", body)
  end

  def delta_status(root, task_id)
    body = Pathname.new("#{root}/tasks/#{task_id}/spec_delta.md").read
    Owl::Validation::Internal::FrontMatterParser.parse(body)[:front_matter]['status']
  end

  it 're-running a successful merge is a clean already_merged skip (no delta_conflict)' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root)
      task_id = create_task(root)
      write_delta(root, task_id, traced_delta)

      first = Owl::Specs::Api.merge_task(root: root, task_id: task_id)
      expect(first.value).to include(ok: true, applied: true, reason: 'merged')

      second = Owl::Specs::Api.merge_task(root: root, task_id: task_id)
      expect(second).to be_ok
      expect(second.value).to include(ok: true, applied: false, reason: 'already_merged', domain: 'billing')
      expect(second.value[:merge]).to be_nil
    end
  end

  it 'flips the delta front-matter status to merged after a non-dry-run apply' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root)
      task_id = create_task(root)
      write_delta(root, task_id, traced_delta)
      expect(delta_status(root, task_id)).to eq('draft')

      Owl::Specs::Api.merge_task(root: root, task_id: task_id)

      expect(delta_status(root, task_id)).to eq('merged')
    end
  end

  it 'does NOT flip the delta status under dry_run' do
    with_tmp_project do |root|
      init_project(root)
      seed_spec(root)
      task_id = create_task(root)
      write_delta(root, task_id, traced_delta)

      Owl::Specs::Api.merge_task(root: root, task_id: task_id, dry_run: true)

      expect(delta_status(root, task_id)).to eq('draft')
    end
  end

  def new_domain_delta
    <<~MD
      ---
      domain: payments
      status: draft
      ---

      ## ADDED Requirements

      ### Requirement: Payouts
      The system SHALL pay out balances.

      #### Scenario: Payout
      - WHEN a payout is due
      - THEN funds are sent
      - TEST: spec/owl/payments_spec.rb
    MD
  end

  it 'dry-run on a brand-new domain traces the preview without spec_not_found and writes nothing' do
    with_tmp_project do |root|
      init_project(root)
      write("#{root}/spec/owl/payments_spec.rb", "# payments\n")
      task_id = create_task(root)
      write_delta(root, task_id, new_domain_delta)

      result = Owl::Specs::Api.merge_task(root: root, task_id: task_id, dry_run: true)

      expect(result).to be_ok
      expect(result.value[:ok]).to be(true)
      expect(result.value[:applied]).to be(false)
      expect(result.value[:trace][:summary][:traced]).to eq(1)
      expect(Pathname.new("#{root}/specs/payments/spec.md").exist?).to be(false)
    end
  end
end
