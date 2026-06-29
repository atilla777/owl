# frozen_string_literal: true

require 'pathname'

# Contract check for the `brief`-step recall surface in owl-step-discussion.
# The skill must invoke `owl recall` (a thin call into the CLI command — no
# reimplemented scoring) and render a "similar archived tasks" block in the
# configured communication language (no hardcoded literals), while never
# blocking the step on an empty/failed recall.
RSpec.describe 'owl-step-discussion brief-step recall surface' do
  let(:skill_body) do
    Pathname.new(File.expand_path('../../../skills/owl-step-discussion/SKILL.md', __dir__)).read
  end

  it 'invokes owl recall with the task title as the query' do
    expect(skill_body).to match(/owl recall ["“]<task\.title>["”] --json/)
  end

  it 'renders a language-neutral "similar archived tasks" heading' do
    expect(skill_body).to match(/similar archived tasks/i)
  end

  it 'states the explicit no-matches line in language-neutral terms' do
    expect(skill_body).to match(/no similar archived\s+tasks\s+found/i)
  end

  it 'carries no hardcoded Cyrillic literals (Language Clause §7)' do
    expect(skill_body).not_to match(/[А-Яа-яЁё]/)
  end

  it 'defers label language to settings.language.communication per §7' do
    expect(skill_body).to match(/settings\.language\.communication/)
    expect(skill_body).to match(/_owl_conventions\.md.*§7|§7.*Language Clause/)
  end

  it 'documents that recall never blocks the brief step' do
    expect(skill_body).to match(/MUST NOT block|never.*block|не.*блок/i)
  end

  it 'does not reimplement scoring in the skill (thin call only)' do
    expect(skill_body).to match(/do \*\*not\*\* reimplement|not reimplement/i)
  end
end
