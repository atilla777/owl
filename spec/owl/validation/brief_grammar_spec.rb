# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/artifacts/api'
require 'owl/cli/api'
require 'owl/validation/api'

# End-to-end coverage for the Requirement/Scenario grammar mandated on the
# seeded `brief` artifact type (P2). Drives the REAL seeded brief validation
# (required_patterns + require_scenarios + require_when_then) through
# `Owl::Validation::Api`, so these tests fail if the shipped config drifts.
RSpec.describe 'Seeded brief Requirement/Scenario grammar' do
  def run_cli(argv, cwd:)
    stdout = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: StringIO.new, env: {}, cwd: cwd.to_s)
    stdout.string
  end

  def setup_task(root)
    run_cli(['init', '--root', root.to_s], cwd: root)
    stdout = run_cli(
      ['task', 'create', '--workflow', 'feature', '--title', 't', '--root', root.to_s, '--json'],
      cwd: root
    )
    JSON.parse(stdout).dig('task', 'id')
  end

  def validate_brief(root, task_id, body)
    write("#{root}/tasks/#{task_id}/brief.md", body)
    result = Owl::Validation::Api.artifact(root: root, task_id: task_id, artifact_key: 'brief')
    expect(result).to be_ok
    result.value
  end

  def violation_types(value)
    value[:violations].map { |v| v[:type] }
  end

  let(:front_matter) { "---\nstatus: draft\nsummary: s\n---\n" }

  def brief(scenarios_block)
    <<~MD
      #{front_matter}
      # Brief

      ## Problem

      p

      ## Goal

      g

      ## Scenarios

      #{scenarios_block}

      ## Edge cases

      - none

      ## Acceptance criteria

      - [ ] done
    MD
  end

  it 'rejects a prose-only brief with a blocking missing_pattern violation' do
    with_tmp_project do |root|
      task_id = setup_task(root)
      value = validate_brief(root, task_id, brief('- happy path, just prose, no requirement'))

      expect(value[:valid]).to be(false)
      missing = value[:violations].find { |v| v[:type] == 'missing_pattern' }
      expect(missing).not_to be_nil
      expect(missing[:level]).to eq('error')
    end
  end

  it 'rejects a Requirement that has no Scenario' do
    with_tmp_project do |root|
      task_id = setup_task(root)
      body = brief(<<~BLOCK)
        ### Requirement: Lonely

        The system SHALL do the thing.
      BLOCK
      value = validate_brief(root, task_id, body)

      expect(value[:valid]).to be(false)
      expect(violation_types(value)).to include('requirement_without_scenario')
    end
  end

  it 'rejects a Scenario that has WHEN but no THEN' do
    with_tmp_project do |root|
      task_id = setup_task(root)
      body = brief(<<~BLOCK)
        ### Requirement: Half-formed

        The system SHALL do the thing.

        #### Scenario: Missing THEN
        - WHEN something happens
      BLOCK
      value = validate_brief(root, task_id, body)

      expect(value[:valid]).to be(false)
      clause = value[:violations].find { |v| v[:type] == 'scenario_missing_clause' }
      expect(clause).not_to be_nil
      expect(clause[:missing]).to eq('THEN')
    end
  end

  it 'accepts a well-formed brief with a Requirement and a WHEN/THEN Scenario' do
    with_tmp_project do |root|
      task_id = setup_task(root)
      body = brief(<<~BLOCK)
        ### Requirement: Well formed

        The system SHALL do the thing.

        #### Scenario: Happy path
        - WHEN something happens
        - THEN the expected outcome is observed
      BLOCK
      value = validate_brief(root, task_id, body)

      expect(value[:valid]).to be(true), "unexpected violations: #{value[:violations]}"
    end
  end

  it 'validates the seeded default brief template verbatim' do
    with_tmp_project do |root|
      task_id = setup_task(root)
      resolved = Owl::Artifacts::Api.resolve(root: root, task_id: task_id, artifact_key: 'brief')
      template = Pathname.new(resolved.value[:template_path]).read

      value = validate_brief(root, task_id, template)
      expect(value[:valid]).to be(true), "template has violations: #{value[:violations]}"
    end
  end
end
