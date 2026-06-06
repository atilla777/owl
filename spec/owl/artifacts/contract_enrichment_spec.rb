# frozen_string_literal: true

require 'owl/artifacts/api'
require 'owl/validation/internal/artifact_runner'

# Behavioural coverage for the enriched plan/review/verification contracts:
# new sections are warning-level (non-breaking) and the new review front matter
# fields are optional but validated when present.
RSpec.describe 'enriched artifact contracts' do
  def seed_project(root)
    write("#{root}/.owl/artifacts.yaml", Owl::Artifacts::Api.default_template)
    Owl::Artifacts::Api.seeded_sources.each do |source|
      write("#{root}/#{source[:relative_path]}", source[:contents])
    end
  end

  def descriptor_for(root, key)
    type = Owl::Artifacts::Api.find(root: root, key: key).value
    { validation: type[:validation], front_matter: type[:front_matter] }
  end

  def violations(root, key, body)
    Owl::Validation::Internal::ArtifactRunner.validate_body(body, descriptor_for(root, key))
  end

  def blocking?(list)
    list.any? { |v| (v[:level] || v['level']).to_s == 'error' }
  end

  it 'keeps a legacy plan (only error sections) valid — new sections are warnings' do
    with_tmp_project do |root|
      seed_project(root)
      legacy = "# Plan\n## Goal\nx\n## Checklist\n- y\n## Smoke test\nz\n"
      list = violations(root, 'plan', legacy)
      expect(blocking?(list)).to be(false)
      # the recommended sections surface as warnings, not errors
      expect(list.map { |v| v[:level] }.uniq).to eq(['warning'])
      expect(list.map { |v| v[:section] }).to include('Scope', 'Out of scope')
    end
  end

  it 'still blocks a plan missing a required (error) section' do
    with_tmp_project do |root|
      seed_project(root)
      missing_goal = "# Plan\n## Checklist\n- y\n## Smoke test\nz\n"
      list = violations(root, 'plan', missing_goal)
      expect(list).to include(a_hash_including(section: 'Goal', level: 'error'))
      expect(blocking?(list)).to be(true)
    end
  end

  it 'accepts a legacy review without verdict/ready front matter' do
    with_tmp_project do |root|
      seed_project(root)
      legacy = "---\nstatus: open\nsummary: ok\n---\n# Review\n## Summary\ns\n## Findings\n- None.\n## Resolution\nr\n"
      expect(blocking?(violations(root, 'review', legacy))).to be(false)
    end
  end

  it 'rejects a review with an invalid verdict enum value' do
    with_tmp_project do |root|
      seed_project(root)
      bad = "---\nstatus: open\nsummary: ok\nverdict: lgtm\n---\n" \
            "# Review\n## Summary\ns\n## Findings\n- None.\n## Resolution\nr\n"
      list = violations(root, 'review', bad)
      expect(blocking?(list)).to be(true)
      expect(list.any? { |v| v[:field].to_s == 'verdict' || v[:description].to_s.include?('verdict') }).to be(true)
    end
  end

  it 'accepts a review with valid verdict + ready' do
    with_tmp_project do |root|
      seed_project(root)
      ok = "---\nstatus: resolved\nsummary: ok\nverdict: accepted\nready: true\n---\n" \
           "# Review\n## Summary\ns\n## Findings\n- None.\n## Resolution\nr\n"
      expect(blocking?(violations(root, 'review', ok))).to be(false)
    end
  end
end
