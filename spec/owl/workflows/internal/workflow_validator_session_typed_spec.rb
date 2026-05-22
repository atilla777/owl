# frozen_string_literal: true

require 'yaml'

require 'owl/workflows/internal/workflow_validator'

RSpec.describe Owl::Workflows::Internal::WorkflowValidator, '.validate session_type + tier' do
  def call(body)
    described_class.validate(root: nil, body: body, source_path: nil)
  end

  let(:base_body) do
    {
      'id' => 'demo',
      'kind' => 'task',
      'title' => 'Demo',
      'artifacts' => {},
      'steps' => [{
        'id' => 'main',
        'session_type' => 'discussion',
        'skill' => 'owl-step-discussion'
      }]
    }
  end

  it 'accepts a step with session_type=discussion and no tier' do
    result = call(base_body)
    expect(result).to be_ok
  end

  it 'accepts a step with session_type=execution and tier=advanced' do
    body = base_body.merge('steps' => [{
                             'id' => 'main',
                             'session_type' => 'execution',
                             'tier' => 'advanced',
                             'skill' => 'owl-step-execution'
                           }])
    result = call(body)
    expect(result).to be_ok
  end

  it 'rejects a step without session_type' do
    body = base_body.merge('steps' => [{ 'id' => 'main', 'skill' => 'owl-step-discussion' }])
    result = call(body)
    expect(result).to be_err
    errors = result.details[:errors]
    paths = errors.map { |e| e[:path] }
    expect(paths).to include('/steps/0/session_type')
  end

  it 'rejects a step with an invalid session_type' do
    body = base_body.merge('steps' => [{
                             'id' => 'main',
                             'session_type' => 'research',
                             'skill' => 'owl-step-discussion'
                           }])
    result = call(body)
    expect(result).to be_err
    messages = result.details[:errors].map { |e| e[:message] }
    expect(messages.join("\n")).to match(/session_type.*must be one of/)
  end

  it 'rejects a step with an invalid tier value' do
    body = base_body.merge('steps' => [{
                             'id' => 'main',
                             'session_type' => 'execution',
                             'tier' => 'turbo',
                             'skill' => 'owl-step-execution'
                           }])
    result = call(body)
    expect(result).to be_err
    messages = result.details[:errors].map { |e| e[:message] }
    expect(messages.join("\n")).to match(/tier.*must be one of/)
  end
end
