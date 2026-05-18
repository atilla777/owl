# frozen_string_literal: true

require 'yaml'
require 'owl/skills/api'
require 'owl/workflows/internal/seeded_sources'

OWL_CLI_REQUIRED_SECTIONS = [
  'Purpose', 'When To Use', 'Source Of Truth', 'Inputs', 'Outputs',
  'CLI Usage', 'Canonical Operations', 'Stop Conditions', 'Verification'
].freeze

OWL_CLI_REQUIRED_COMMANDS = [
  'init', 'workflow list', 'config validate', 'task create',
  'task ready-steps', 'step invocation', 'step show',
  'artifact resolve', 'artifact validate',
  'publish', 'archive', 'instructions', 'status'
].freeze

OWL_STEP_RUN_REQUIRED_SECTIONS = [
  'Purpose', 'When To Use', 'Inputs', 'Outputs',
  'Workflow', 'Stop Conditions', 'Verification'
].freeze

OWL_STEP_RUN_REQUIRED_COMMANDS = [
  'owl step show', 'owl artifact resolve', 'owl artifact validate', 'owl step complete'
].freeze

OWL_STEP_RUN_HARDCODED_STEP_IDS = %w[
  brief specify design plan apply verify publish archive
  decompose coordinate aggregate_verify
  issue patch_plan tasks
  question findings options recommendation
].freeze

OWL_ORCHESTRATOR_REQUIRED_SECTIONS = [
  'Purpose', 'When To Use', 'Inputs', 'Outputs',
  'Workflow', 'Stop Conditions', 'Notes'
].freeze

RSpec.describe Owl::Skills::Internal::SeededSources do
  let(:files) { Owl::Skills::Api.seeded_sources }
  let(:paths) { files.map { |entry| entry[:relative_path] } }

  let(:seeded_workflow_step_ids) do
    workflows = Owl::Workflows::Internal::SeededSources.files
    workflows.flat_map do |entry|
      YAML.safe_load(entry[:contents]).fetch('steps').map { |step| step['id'] }
    end.uniq
  end

  describe '1-to-1 coverage between seeded workflow steps and seeded skills' do
    it 'has a SKILL.md for every step id mentioned in seeded workflows' do
      missing = seeded_workflow_step_ids.reject do |step_id|
        paths.include?(".claude/skills/owl-step-#{step_id}/SKILL.md")
      end
      expect(missing).to be_empty,
                         -> { "missing SKILL.md for step ids: #{missing.inspect}" }
    end

    it 'has a slash-command for every SKILL.md' do
      skill_dirs = paths.grep(%r{\A\.claude/skills/(owl-step-[a-z_]+)/SKILL\.md\z}) { Regexp.last_match(1) }
      missing = skill_dirs.reject do |skill_id|
        paths.include?(".claude/commands/#{skill_id}.md")
      end
      expect(missing).to be_empty,
                         -> { "missing slash-command for skills: #{missing.inspect}" }
    end
  end

  describe 'SKILL.md content' do
    let(:skill_md_files) { files.select { |entry| entry[:relative_path].end_with?('/SKILL.md') } }

    it 'has valid YAML front-matter with name, description, triggers' do
      skill_md_files.each do |entry|
        fm_match = entry[:contents].match(/\A---\n(.*?)\n---/m)
        expect(fm_match).not_to be_nil,
                                -> { "missing frontmatter in #{entry[:relative_path]}" }
        parsed = YAML.safe_load(fm_match[1])
        expect(parsed).to include('name', 'description', 'triggers')
        expect(parsed['triggers']).to be_an(Array)
        expect(parsed['triggers']).not_to be_empty
      end
    end

    it 'declares `name` matching its containing directory' do
      skill_md_files.each do |entry|
        dir_name = entry[:relative_path].match(%r{\.claude/skills/([^/]+)/SKILL\.md})[1]
        fm = YAML.safe_load(entry[:contents].match(/\A---\n(.*?)\n---/m)[1])
        expect(fm['name']).to eq(dir_name),
                              -> { "name=#{fm['name']} does not match dir=#{dir_name}" }
      end
    end

    it 'has the required body sections (Purpose, When to use, Inputs, Outputs, Workflow) for step skills' do
      step_skill_ids = described_class.step_skill_ids
      step_skill_files = skill_md_files.select do |entry|
        match = entry[:relative_path].match(%r{\.claude/skills/([^/]+)/SKILL\.md})
        match && step_skill_ids.include?(match[1])
      end
      step_skill_files.each do |entry|
        %w[Purpose When\ to\ use Inputs Outputs Workflow].each do |section|
          expect(entry[:contents]).to include("## #{section}"),
                                      -> { "#{entry[:relative_path]} missing section '## #{section}'" }
        end
      end
    end
  end

  describe '.step_skill_ids' do
    it 'covers exactly the seeded workflow step ids' do
      expect(described_class.step_skill_ids.sort).to eq(seeded_workflow_step_ids.map { |id| "owl-step-#{id}" }.sort)
    end
  end

  describe 'owl-cli skill' do
    let(:skill_entry) do
      files.find { |entry| entry[:relative_path] == '.claude/skills/owl-cli/SKILL.md' }
    end
    let(:slash_entry) do
      files.find { |entry| entry[:relative_path] == '.claude/commands/owl-cli.md' }
    end

    it 'materializes a SKILL.md and a slash-command file' do
      expect(skill_entry).not_to be_nil, 'expected owl-cli SKILL.md in seeded sources'
      expect(slash_entry).not_to be_nil, 'expected owl-cli slash-command in seeded sources'
    end

    it 'has frontmatter with name: owl-cli and a non-empty description' do
      fm = YAML.safe_load(skill_entry[:contents].match(/\A---\n(.*?)\n---/m)[1])
      expect(fm['name']).to eq('owl-cli')
      expect(fm['description']).to be_a(String)
      expect(fm['description']).not_to be_empty
    end

    it 'documents the kos-api-style sections so downstream skills can rely on it' do
      OWL_CLI_REQUIRED_SECTIONS.each do |section|
        expect(skill_entry[:contents]).to include("## #{section}"),
                                          -> { "owl-cli SKILL.md missing section '## #{section}'" }
      end
    end

    it 'references the agent-facing bin/owl commands so downstream skills know what is covered' do
      OWL_CLI_REQUIRED_COMMANDS.each do |command|
        expect(skill_entry[:contents]).to include(command),
                                          -> { "owl-cli SKILL.md does not mention `#{command}`" }
      end
    end

    it 'loads the skill from the slash-command body' do
      expect(slash_entry[:contents]).to include('Load skill `owl-cli`')
    end
  end

  describe 'owl-step-run skill' do
    let(:skill_entry) do
      files.find { |entry| entry[:relative_path] == '.claude/skills/owl-step-run/SKILL.md' }
    end
    let(:slash_entry) do
      files.find { |entry| entry[:relative_path] == '.claude/commands/owl-step-run.md' }
    end

    it 'materializes a SKILL.md and a slash-command file' do
      expect(skill_entry).not_to be_nil, 'expected owl-step-run SKILL.md in seeded sources'
      expect(slash_entry).not_to be_nil, 'expected owl-step-run slash-command in seeded sources'
    end

    it 'has frontmatter with name: owl-step-run, non-empty description, and non-empty triggers' do
      fm = YAML.safe_load(skill_entry[:contents].match(/\A---\n(.*?)\n---/m)[1])
      expect(fm['name']).to eq('owl-step-run')
      expect(fm['description']).to be_a(String)
      expect(fm['description']).not_to be_empty
      expect(fm['triggers']).to be_an(Array)
      expect(fm['triggers']).not_to be_empty
    end

    it 'documents the seeded-skill body sections so downstream agents know the flow' do
      OWL_STEP_RUN_REQUIRED_SECTIONS.each do |section|
        expect(skill_entry[:contents]).to include("## #{section}"),
                                          -> { "owl-step-run SKILL.md missing section '## #{section}'" }
      end
    end

    it 'references the canonical step-execution CLI commands' do
      OWL_STEP_RUN_REQUIRED_COMMANDS.each do |command|
        expect(skill_entry[:contents]).to include(command),
                                          -> { "owl-step-run SKILL.md does not mention `#{command}`" }
      end
    end

    it 'does not reference any specific owl-step-<id> skill (no hardcoded step type knowledge)' do
      OWL_STEP_RUN_HARDCODED_STEP_IDS.each do |id|
        expect(skill_entry[:contents]).not_to include("owl-step-#{id}"),
                                              -> { "owl-step-run SKILL.md references hardcoded `owl-step-#{id}`" }
      end
    end

    it 'points downstream readers at the owl-cli skill for the CLI surface' do
      expect(skill_entry[:contents]).to include('owl-cli'),
                                        -> { 'owl-step-run SKILL.md should reference owl-cli as the CLI reference' }
    end

    it 'loads the skill from the slash-command body' do
      expect(slash_entry[:contents]).to include('Load skill `owl-step-run`')
    end
  end

  describe 'owl-orchestrator skill' do
    let(:skill_entry) do
      files.find { |entry| entry[:relative_path] == '.claude/skills/owl-orchestrator/SKILL.md' }
    end
    let(:slash_entry) do
      files.find { |entry| entry[:relative_path] == '.claude/commands/owl-orchestrator.md' }
    end

    it 'materializes a SKILL.md and a slash-command file' do
      expect(skill_entry).not_to be_nil, 'expected owl-orchestrator SKILL.md in seeded sources'
      expect(slash_entry).not_to be_nil, 'expected owl-orchestrator slash-command in seeded sources'
    end

    it 'has frontmatter with name: owl-orchestrator, non-empty description, non-empty triggers' do
      fm = YAML.safe_load(skill_entry[:contents].match(/\A---\n(.*?)\n---/m)[1])
      expect(fm['name']).to eq('owl-orchestrator')
      expect(fm['description']).to be_a(String)
      expect(fm['description']).not_to be_empty
      expect(fm['triggers']).to be_an(Array)
      expect(fm['triggers']).not_to be_empty
    end

    it 'documents the required body sections including Stop Conditions' do
      OWL_ORCHESTRATOR_REQUIRED_SECTIONS.each do |section|
        expect(skill_entry[:contents]).to include("## #{section}"),
                                          -> { "owl-orchestrator SKILL.md missing section '## #{section}'" }
      end
    end

    it 'references the universal owl-step-run executor and the owl-cli reference skill' do
      contents = skill_entry[:contents]
      expect(contents).to include('owl-step-run'),
                          -> { 'owl-orchestrator SKILL.md should reference owl-step-run' }
      expect(contents).to include('owl-cli'),
                          -> { 'owl-orchestrator SKILL.md should reference owl-cli' }
    end

    it 'does not hardcode per-step skill names as the only delegation target' do
      message = 'owl-orchestrator SKILL.md still uses deprecated `owl-step-<step.id>` placeholder'
      expect(skill_entry[:contents]).not_to include('owl-step-<step.id>'), message
    end

    it 'documents owl instructions as the skill-binding source' do
      message = 'owl-orchestrator SKILL.md should describe owl instructions as binding source'
      expect(skill_entry[:contents]).to include('owl instructions'), message
    end
  end
end
