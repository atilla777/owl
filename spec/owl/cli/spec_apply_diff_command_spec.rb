# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'owl spec apply/diff CLI' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def init_project(root)
    run(['init', '--root', root.to_s], cwd: root)
  end

  def seed_spec(root)
    write("#{root}/specs/billing/spec.md", <<~MD)
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
    MD
  end

  def add_delta(root)
    write("#{root}/d.md", <<~MD)
      ## ADDED Requirements

      ### Requirement: Late fees

      The system SHALL charge late fees.

      #### Scenario: Late
      - WHEN payment is late
      - THEN a fee is added
    MD
  end

  describe 'spec diff' do
    it 'routes to SpecDiff and prints the unified diff without writing' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root)
        add_delta(root)
        before = Pathname.new("#{root}/specs/billing/spec.md").read

        argv = ['spec', 'diff', 'billing', '--delta', "#{root}/d.md", '--root', root.to_s, '--json']
        exit_code, stdout, = run(argv, cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['valid']).to be(true)
        expect(body['unified_diff']).to include('+### Requirement: Late fees')
        expect(Pathname.new("#{root}/specs/billing/spec.md").read).to eq(before)
      end
    end

    it 'requires the DOMAIN positional argument' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(['spec', 'diff', '--delta', "#{root}/d.md", '--root', root.to_s], cwd: root)
        expect(exit_code).not_to eq(0)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'requires the --delta option' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(['spec', 'diff', 'billing', '--root', root.to_s], cwd: root)
        expect(exit_code).not_to eq(0)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end

  describe 'spec apply' do
    it 'routes to SpecApply and writes the merged spec' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root)
        add_delta(root)

        argv = ['spec', 'apply', 'billing', '--delta', "#{root}/d.md", '--root', root.to_s, '--json']
        exit_code, stdout, = run(argv, cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['dry_run']).to be(false)
        expect(body['applied']).to eq('added' => 1, 'modified' => 0, 'removed' => 0)
        expect(Pathname.new("#{root}/specs/billing/spec.md").read).to include('### Requirement: Late fees')
      end
    end

    it 'does not write with --dry-run' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root)
        add_delta(root)
        before = Pathname.new("#{root}/specs/billing/spec.md").read

        argv = ['spec', 'apply', 'billing', '--delta', "#{root}/d.md", '--dry-run', '--root', root.to_s, '--json']
        exit_code, stdout, = run(argv, cwd: root)
        expect(exit_code).to eq(0)
        expect(JSON.parse(stdout)['dry_run']).to be(true)
        expect(Pathname.new("#{root}/specs/billing/spec.md").read).to eq(before)
      end
    end

    it 'surfaces merge_would_invalidate as a failure with violations' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root)
        write("#{root}/d.md", <<~MD)
          ## MODIFIED Requirements

          ### Requirement: Invoices

          The system SHALL issue invoices but has no scenario.
        MD

        argv = ['spec', 'apply', 'billing', '--delta', "#{root}/d.md", '--root', root.to_s, '--json']
        exit_code, _stdout, stderr = run(argv, cwd: root)
        expect(exit_code).not_to eq(0)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('merge_would_invalidate')
      end
    end

    it 'requires the --delta option' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(['spec', 'apply', 'billing', '--root', root.to_s], cwd: root)
        expect(exit_code).not_to eq(0)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end

    it 'requires the DOMAIN positional argument' do
      with_tmp_project do |root|
        init_project(root)
        exit_code, _stdout, stderr = run(['spec', 'apply', '--delta', "#{root}/d.md", '--root', root.to_s], cwd: root)
        expect(exit_code).not_to eq(0)
        expect(JSON.parse(stderr).dig('error', 'code')).to eq('invalid_arguments')
      end
    end
  end
end
