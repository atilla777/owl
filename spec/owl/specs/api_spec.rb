# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'

require 'owl/cli/api'
require 'owl/specs/api'

RSpec.describe Owl::Specs::Api do
  def run_cli(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
  end

  def init_project(root)
    run_cli(['init', '--root', root.to_s], cwd: root)
  end

  def seed_spec(root, domain, body)
    write("#{root}/specs/#{domain}/spec.md", body)
  end

  def template_body(root)
    Pathname.new("#{root}/.owl/artifacts/spec/templates/default.md").read
  end

  describe '.path' do
    it 'resolves a domain to <root>/specs/<domain>/spec.md via the specs role' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.path(root: root, domain: 'ui')
        expect(result).to be_ok
        expect(result.value).to eq(domain: 'ui', path: "#{root}/specs/ui/spec.md")
      end
    end

    it 'rejects an unsafe domain slug before resolving any path' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.path(root: root, domain: '../escape')
        expect(result).to be_err
        expect(result.code).to eq(:invalid_domain)
        expect(result.details[:domain]).to eq('../escape')
      end
    end
  end

  describe '.list' do
    it 'returns an empty list (not an error) when no specs exist' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.list(root: root)
        expect(result).to be_ok
        expect(result.value).to eq([])
      end
    end

    it 'enumerates every domain holding a spec.md, sorted, ignoring bare dirs' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root, 'ui', template_body(root))
        seed_spec(root, 'billing', template_body(root))
        write("#{root}/specs/empty/README.txt", 'no spec here')

        result = described_class.list(root: root)
        expect(result).to be_ok
        expect(result.value).to eq(
          [
            { domain: 'billing', path: "#{root}/specs/billing/spec.md" },
            { domain: 'ui', path: "#{root}/specs/ui/spec.md" }
          ]
        )
      end
    end
  end

  describe '.show' do
    it 'returns the raw body for an existing spec' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root, 'ui', "raw body\n")
        result = described_class.show(root: root, domain: 'ui')
        expect(result).to be_ok
        expect(result.value[:domain]).to eq('ui')
        expect(result.value[:body]).to eq("raw body\n")
      end
    end

    it 'returns spec_not_found with available domains for a missing spec' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root, 'billing', template_body(root))
        result = described_class.show(root: root, domain: 'nope')
        expect(result).to be_err
        expect(result.code).to eq(:spec_not_found)
        expect(result.details[:available]).to eq(['billing'])
      end
    end

    it 'rejects an invalid domain' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.show(root: root, domain: 'Bad/Slash')
        expect(result).to be_err
        expect(result.code).to eq(:invalid_domain)
      end
    end
  end

  describe '.validate' do
    it 'validates a clean spec (the seeded template) as valid with no violations' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root, 'ui', template_body(root))
        result = described_class.validate(root: root, domain: 'ui')
        expect(result).to be_ok
        expect(result.value[:valid]).to be(true)
        expect(result.value[:violations]).to eq([])
        expect(result.value[:path]).to eq("#{root}/specs/ui/spec.md")
      end
    end

    it 'surfaces requirement_without_scenario as a blocking violation' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root, 'ui', <<~MD)
          ---
          status: draft
          summary: A spec with a requirement that has no scenario.
          ---

          ## Purpose

          Purpose text.

          ## Requirements

          ### Requirement: Lonely requirement

          The system SHALL do something, but declares no scenario.
        MD

        result = described_class.validate(root: root, domain: 'ui')
        expect(result).to be_ok
        expect(result.value[:valid]).to be(false)
        types = result.value[:violations].map { |v| v[:type] }
        expect(types).to include('requirement_without_scenario')
      end
    end

    it 'returns spec_not_found when validating a non-existent spec (no crash)' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.validate(root: root, domain: 'ghost')
        expect(result).to be_err
        expect(result.code).to eq(:spec_not_found)
      end
    end

    it 'propagates the error when the spec artifact type is not registered' do
      with_tmp_project do |root|
        init_project(root)
        seed_spec(root, 'ui', template_body(root))
        # Simulate a project whose registry predates the spec artifact type.
        write("#{root}/.owl/artifacts.yaml", <<~YAML)
          schema_version: 1
          artifacts:
            brief:
              source: "artifacts/brief/artifact.yaml"
        YAML

        result = described_class.validate(root: root, domain: 'ui')
        expect(result).to be_err
        expect(result.code).to eq(:unknown_artifact_type)
      end
    end
  end
end
