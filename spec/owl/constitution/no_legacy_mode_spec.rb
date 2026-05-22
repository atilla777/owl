# frozen_string_literal: true

# Constitution meta-spec: RFC #1 §7 (knowledge entry 46) declares the
# session_type migration a breaking switch with no legacy mode. This spec
# enforces that nothing in `lib/owl/` or `skills/` reintroduces a
# `--legacy` flag, an `OWL_LEGACY` env var, a `legacy_mode` symbol, or
# the removed step-level `interactive:` schema field.

require 'json'

require 'owl/internal/paths'

module OwlNoLegacyFixtures
  ROOT = File.expand_path('../../..', __dir__)
end

RSpec.describe 'Owl constitution: no legacy mode after RFC #1 switch' do
  def grep(roots, pattern)
    matches = []
    roots.each do |root|
      next unless File.directory?(root)

      Dir.glob(File.join(root, '**', '*')).each do |path|
        next unless File.file?(path)
        next if File.extname(path) == '.lock'

        File.readlines(path).each_with_index do |line, idx|
          next if line.lstrip.start_with?('#')
          next unless pattern.match?(line)

          matches << "#{path.delete_prefix("#{OwlNoLegacyFixtures::ROOT}/")}:#{idx + 1}"
        end
      end
    end
    matches
  end

  let(:lib_root) { File.join(OwlNoLegacyFixtures::ROOT, 'lib', 'owl') }
  let(:skills_root) { File.join(OwlNoLegacyFixtures::ROOT, 'skills') }
  let(:workflows_root) { File.join(OwlNoLegacyFixtures::ROOT, 'workflows') }
  let(:commands_root) { File.join(OwlNoLegacyFixtures::ROOT, 'commands') }

  it 'has no `--legacy` flag anywhere in lib/owl/ or skills/' do
    offenders = grep([lib_root, skills_root], /--legacy\b/)
    expect(offenders).to be_empty,
                         -> { "found `--legacy` references: #{offenders.inspect}" }
  end

  it 'has no `OWL_LEGACY` env-var reference anywhere in lib/owl/ or skills/' do
    offenders = grep([lib_root, skills_root], /\bOWL_LEGACY\b/)
    expect(offenders).to be_empty,
                         -> { "found `OWL_LEGACY` references: #{offenders.inspect}" }
  end

  it 'has no `legacy_mode` symbol or string in lib/owl/ or skills/' do
    offenders = grep([lib_root, skills_root], /\blegacy_mode\b/)
    expect(offenders).to be_empty,
                         -> { "found `legacy_mode` references: #{offenders.inspect}" }
  end

  it 'has no surviving `owl-step-run` skill or slash-command' do
    skill = File.join(skills_root, 'owl-step-run', 'SKILL.md')
    command = File.join(commands_root, 'owl-step-run.md')
    expect(File.exist?(skill)).to be(false), 'skills/owl-step-run/SKILL.md still exists'
    expect(File.exist?(command)).to be(false), 'commands/owl-step-run.md still exists'
  end

  it 'has no `interactive:` step-level field in seeded workflow YAMLs' do
    offenders = grep([workflows_root], /^\s+interactive:\s/)
    expect(offenders).to be_empty,
                         -> { "interactive: field still present: #{offenders.inspect}" }
  end

  describe 'schemas/workflow.json' do
    let(:schema_path) { File.join(OwlNoLegacyFixtures::ROOT, 'schemas', 'workflow.json') }
    let(:schema) { JSON.parse(File.read(schema_path)) }

    it 'declares step.properties.session_type as a required enum' do
      session = schema.dig('$defs', 'step', 'properties', 'session_type')
      expect(session['type']).to eq('string')
      expect(session['enum']).to contain_exactly('discussion', 'execution')
      expect(schema.dig('$defs', 'step', 'required')).to include('session_type')
    end

    it 'declares step.properties.tier as an optional enum' do
      tier = schema.dig('$defs', 'step', 'properties', 'tier')
      expect(tier['type']).to eq('string')
      expect(tier['enum']).to contain_exactly('standard', 'advanced')
      expect(schema.dig('$defs', 'step', 'required') || []).not_to include('tier')
    end

    it 'no longer declares `interactive` on step or step_variant' do
      step_props = schema.dig('$defs', 'step', 'properties') || {}
      variant_props = schema.dig('$defs', 'step_variant', 'properties') || {}
      expect(step_props).not_to include('interactive')
      expect(variant_props).not_to include('interactive')
    end
  end
end
