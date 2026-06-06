# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'

require 'owl/cli/api'
require 'owl/specs/api'

RSpec.describe 'Owl::Specs::Api delta merge' do
  def run_cli(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
  end

  def init_project(root)
    run_cli(['init', '--root', root.to_s], cwd: root)
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

      ## Notes

      trailing
    MD
  end

  def add_delta(root, name: 'Late fees')
    write("#{root}/d.md", <<~MD)
      ## ADDED Requirements

      ### Requirement: #{name}

      The system SHALL charge late fees.

      #### Scenario: Late
      - WHEN payment is late
      - THEN a fee is added
    MD
  end

  describe '.apply' do
    it 'appends an ADDED requirement and writes the merged spec' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root)
        add_delta(root)

        result = Owl::Specs::Api.apply(root: root, domain: 'billing', delta_path: "#{root}/d.md")
        expect(result).to be_ok
        expect(result.value[:applied]).to eq(added: 1, modified: 0, removed: 0)
        expect(result.value[:dry_run]).to be(false)

        on_disk = Pathname.new("#{root}/specs/billing/spec.md").read
        expect(on_disk).to include('### Requirement: Late fees')
        expect(on_disk).to include('## Notes')
      end
    end

    it 'is deterministic — applying the same delta twice yields identical bytes' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root)
        add_delta(root)

        first = Owl::Specs::Api.diff(root: root, domain: 'billing', delta_path: "#{root}/d.md").value[:after]
        second = Owl::Specs::Api.diff(root: root, domain: 'billing', delta_path: "#{root}/d.md").value[:after]
        expect(first).to eq(second)
      end
    end

    it 'does not write on --dry-run' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root)
        add_delta(root)
        before = Pathname.new("#{root}/specs/billing/spec.md").read

        result = Owl::Specs::Api.apply(root: root, domain: 'billing', delta_path: "#{root}/d.md", dry_run: true)
        expect(result).to be_ok
        expect(result.value[:dry_run]).to be(true)
        expect(Pathname.new("#{root}/specs/billing/spec.md").read).to eq(before)
      end
    end

    it 'creates a spec from a minimal scaffold when absent and delta is ADDED-only' do
      with_tmp_project do |root|
        init_project(root)
        add_delta(root)

        result = Owl::Specs::Api.apply(root: root, domain: 'fresh', delta_path: "#{root}/d.md")
        expect(result).to be_ok
        expect(result.value[:created]).to be(true)

        validation = Owl::Specs::Api.validate(root: root, domain: 'fresh')
        expect(validation.value[:valid]).to be(true)
      end
    end

    it 'returns spec_not_found for MODIFIED/REMOVED against a missing spec' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/d.md", "## REMOVED Requirements\n\n### Requirement: Ghost\n")

        result = Owl::Specs::Api.apply(root: root, domain: 'ghostdomain', delta_path: "#{root}/d.md")
        expect(result).to be_err
        expect(result.code).to eq(:spec_not_found)
      end
    end

    it 'returns delta_conflict and writes nothing when ADDED already exists' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root)
        write("#{root}/d.md", <<~MD)
          ## ADDED Requirements

          ### Requirement: Invoices

          The system SHALL issue invoices.

          #### Scenario: S
          - WHEN x
          - THEN y
        MD
        before = Pathname.new("#{root}/specs/billing/spec.md").read

        result = Owl::Specs::Api.apply(root: root, domain: 'billing', delta_path: "#{root}/d.md")
        expect(result).to be_err
        expect(result.code).to eq(:delta_conflict)
        expect(Pathname.new("#{root}/specs/billing/spec.md").read).to eq(before)
      end
    end

    it 'returns delta_not_found when the delta file is missing' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root)

        result = Owl::Specs::Api.apply(root: root, domain: 'billing', delta_path: "#{root}/missing.md")
        expect(result).to be_err
        expect(result.code).to eq(:delta_not_found)
      end
    end

    it 'returns invalid_domain before resolving anything' do
      with_tmp_project do |root|
        init_project(root)
        add_delta(root)

        result = Owl::Specs::Api.apply(root: root, domain: '../escape', delta_path: "#{root}/d.md")
        expect(result).to be_err
        expect(result.code).to eq(:invalid_domain)
      end
    end

    it 'aborts with merge_would_invalidate and writes nothing when the merge breaks the grammar' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root)
        # A modified requirement with no scenario violates require_scenarios.
        write("#{root}/d.md", <<~MD)
          ## MODIFIED Requirements

          ### Requirement: Invoices

          The system SHALL issue invoices but has no scenario now.
        MD
        before = Pathname.new("#{root}/specs/billing/spec.md").read

        result = Owl::Specs::Api.apply(root: root, domain: 'billing', delta_path: "#{root}/d.md")
        expect(result).to be_err
        expect(result.code).to eq(:merge_would_invalidate)
        expect(result.details[:violations].map { |v| v[:type] }).to include('requirement_without_scenario')
        expect(Pathname.new("#{root}/specs/billing/spec.md").read).to eq(before)
      end
    end

    it 'propagates invalid_delta from the delta parser' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root)
        write("#{root}/d.md", "## BOGUS Requirements\n\n### Requirement: X\n\nThe system SHALL x.\n")

        result = Owl::Specs::Api.apply(root: root, domain: 'billing', delta_path: "#{root}/d.md")
        expect(result).to be_err
        expect(result.code).to eq(:invalid_delta)
      end
    end
  end

  describe '.diff' do
    it 'previews the unified diff and validity without writing' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root)
        add_delta(root)
        before = Pathname.new("#{root}/specs/billing/spec.md").read

        result = Owl::Specs::Api.diff(root: root, domain: 'billing', delta_path: "#{root}/d.md")
        expect(result).to be_ok
        expect(result.value[:valid]).to be(true)
        expect(result.value[:unified_diff]).to include('+### Requirement: Late fees')
        expect(Pathname.new("#{root}/specs/billing/spec.md").read).to eq(before)
      end
    end

    it 'previews a would-be-invalid merge with valid:false instead of erroring' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root)
        write("#{root}/d.md", <<~MD)
          ## MODIFIED Requirements

          ### Requirement: Invoices

          The system SHALL issue invoices but has no scenario now.
        MD

        result = Owl::Specs::Api.diff(root: root, domain: 'billing', delta_path: "#{root}/d.md")
        expect(result).to be_ok
        expect(result.value[:valid]).to be(false)
      end
    end

    it 'propagates hard errors (delta_not_found)' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root)

        result = Owl::Specs::Api.diff(root: root, domain: 'billing', delta_path: "#{root}/nope.md")
        expect(result).to be_err
        expect(result.code).to eq(:delta_not_found)
      end
    end
  end
end
