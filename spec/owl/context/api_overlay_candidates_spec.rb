# frozen_string_literal: true

require 'owl/context/api'

RSpec.describe Owl::Context::Api, '.overlay_candidates' do
  it 'lists candidate paths in resolution order with presence flags' do
    with_tmp_project do |root|
      write("#{root}/.owl/overlays/plan.md", "Project plan note.\n")
      result = described_class.overlay_candidates(root: root, step_id: 'plan')
      expect(result).to be_ok
      first = result.value.first
      expect(first[:path]).to end_with('.owl/overlays/plan.md')
      expect(first[:present]).to be(true)
      expect(first[:bytes]).to be > 0
      # docs/ai/plan.md candidate is enumerated but absent
      expect(result.value.map { |c| c[:present] }).to include(false)
    end
  end

  it 'includes variant-specific candidates when a variant is given' do
    with_tmp_project do |root|
      result = described_class.overlay_candidates(root: root, step_id: 'brief', variant: 'problem_inventory')
      paths = result.value.map { |c| c[:path] }
      expect(paths).to include(a_string_ending_with('.owl/overlays/brief/problem_inventory.md'))
    end
  end

  it 'reports a present-but-empty stub as present even though it does not apply' do
    with_tmp_project do |root|
      write("#{root}/.owl/overlays/plan.md", "<!-- stub only -->\n")
      candidates = described_class.overlay_candidates(root: root, step_id: 'plan').value
      applied = described_class.overlays_for(root: root, step_id: 'plan').value
      expect(candidates.first[:present]).to be(true)
      expect(applied).to be_empty
    end
  end
end
