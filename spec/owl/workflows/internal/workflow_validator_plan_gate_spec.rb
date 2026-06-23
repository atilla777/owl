# frozen_string_literal: true

require 'owl/workflows/internal/workflow_validator'

RSpec.describe Owl::Workflows::Internal::WorkflowValidator, '.validate plan_approved gate' do
  def call(body)
    described_class.validate(root: nil, body: body, source_path: nil)
  end

  def step(id, extra = {})
    { 'id' => id, 'session_type' => 'execution' }.merge(extra)
  end

  it 'accepts gate: plan_approved when a plan step exists' do
    body = {
      'id' => 'feat', 'kind' => 'task', 'artifacts' => {},
      'steps' => [
        step('plan', 'session_type' => 'discussion'),
        step('implement', 'requires' => ['plan'], 'gate' => 'plan_approved')
      ]
    }
    expect(call(body)).to be_ok
  end

  it 'rejects gate: plan_approved when there is no plan step (gate_requires_plan)' do
    body = {
      'id' => 'feat', 'kind' => 'task', 'artifacts' => {},
      'steps' => [
        step('design', 'session_type' => 'discussion'),
        step('implement', 'requires' => ['design'], 'gate' => 'plan_approved')
      ]
    }
    result = call(body)
    expect(result).to be_err
    codes = result.details[:errors].map { |e| e[:code] }
    expect(codes).to include('gate_requires_plan')
  end

  it 'leaves children_complete untouched (no plan requirement)' do
    body = {
      'id' => 'comp', 'kind' => 'composite_task', 'artifacts' => {},
      'steps' => [
        step('decompose', 'session_type' => 'discussion'),
        step('archive', 'requires' => ['decompose'], 'gate' => 'children_complete')
      ]
    }
    expect(call(body)).to be_ok
  end

  it 'keeps a workflow without any gate valid (back-compat)' do
    body = {
      'id' => 'feat', 'kind' => 'task', 'artifacts' => {},
      'steps' => [step('plan', 'session_type' => 'discussion'), step('implement', 'requires' => ['plan'])]
    }
    expect(call(body)).to be_ok
  end
end
