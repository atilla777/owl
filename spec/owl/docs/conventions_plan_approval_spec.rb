# frozen_string_literal: true

# Guards the documentation acceptance criterion: `_owl_conventions.md` must
# describe default autonomy as a deliberate trade-off and explain how to enable
# the optional plan-approval gate.
RSpec.describe '_owl_conventions.md plan-approval documentation' do
  let(:body) do
    path = File.expand_path('../../../skills/_owl_conventions.md', __dir__)
    File.read(path)
  end

  it 'documents the autonomy-by-default trade-off' do
    expect(body).to match(/trade-off/i)
    expect(body).to match(/autonomous by default|autonomy.*default|default.*autonom/i)
    expect(body).to match(/pros/i).or match(/cons/i)
  end

  it 'explains how to enable the opt-in plan-approval gate' do
    expect(body).to include('gate: plan_approved')
    expect(body).to include('owl plan approve')
  end
end
