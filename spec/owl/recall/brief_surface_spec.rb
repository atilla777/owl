# frozen_string_literal: true

require 'pathname'

# Contract check for the `brief`-step recall surface in owl-step-discussion.
# The skill must invoke `owl recall` (a thin call into the CLI command — no
# reimplemented scoring) and render a «Похожие архивные задачи» block, while
# never blocking the step on an empty/failed recall.
RSpec.describe 'owl-step-discussion brief-step recall surface' do
  let(:skill_body) do
    Pathname.new(File.expand_path('../../../skills/owl-step-discussion/SKILL.md', __dir__)).read
  end

  it 'invokes owl recall with the task title as the query' do
    expect(skill_body).to match(/owl recall ["“]<task\.title>["”] --json/)
  end

  it 'renders the «Похожие архивные задачи» block' do
    expect(skill_body).to include('Похожие архивные задачи')
  end

  it 'states the explicit no-matches line' do
    expect(skill_body).to include('похожих архивных задач не найдено')
  end

  it 'documents that recall never blocks the brief step' do
    expect(skill_body).to match(/MUST NOT block|never.*block|не.*блок/i)
  end

  it 'does not reimplement scoring in the skill (thin call only)' do
    expect(skill_body).to match(/do \*\*not\*\* reimplement|not reimplement/i)
  end
end
