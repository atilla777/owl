# frozen_string_literal: true

require 'owl/workflows/internal/workflow_validator'

RSpec.describe Owl::Workflows::Internal::WorkflowValidator, '.validate when: predicate' do
  def call(body)
    described_class.validate(root: nil, body: body, source_path: nil)
  end

  def body_with(when_clause)
    {
      'id' => 'feat', 'kind' => 'task', 'artifacts' => { 'brief' => {} },
      'steps' => [
        { 'id' => 'brief', 'session_type' => 'discussion' },
        { 'id' => 'design', 'session_type' => 'discussion', 'requires' => ['brief'], 'when' => when_clause }
      ]
    }
  end

  def error_codes_and_paths(result)
    result.details[:errors].map { |e| [e[:path], e[:message]] }
  end

  it 'accepts a well-formed matches predicate' do
    expect(call(body_with('artifact' => 'brief', 'matches' => 'needs design'))).to be_ok
  end

  it 'accepts a well-formed not_matches predicate' do
    expect(call(body_with('artifact' => 'brief', 'not_matches' => '^skip'))).to be_ok
  end

  it 'rejects a predicate declaring both matches and not_matches' do
    result = call(body_with('artifact' => 'brief', 'matches' => 'a', 'not_matches' => 'b'))
    expect(result).to be_err
    expect(error_codes_and_paths(result).map(&:last))
      .to include(a_string_matching(%r{exactly one of `matches` / `not_matches`}))
  end

  it 'rejects a predicate declaring neither operator' do
    result = call(body_with('artifact' => 'brief'))
    expect(result).to be_err
    expect(error_codes_and_paths(result).map(&:last))
      .to include(a_string_matching(/exactly one of/))
  end

  it 'rejects a missing/empty artifact key' do
    result = call(body_with('artifact' => '  ', 'matches' => 'x'))
    expect(result).to be_err
    expect(error_codes_and_paths(result).map(&:first)).to include('/steps/1/when/artifact')
  end

  it 'rejects an uncompilable regex' do
    result = call(body_with('artifact' => 'brief', 'matches' => '('))
    expect(result).to be_err
    expect(error_codes_and_paths(result).map(&:last))
      .to include(a_string_matching(/not a valid regex/))
  end

  it 'rejects an empty matches string' do
    result = call(body_with('artifact' => 'brief', 'matches' => ''))
    expect(result).to be_err
    expect(error_codes_and_paths(result).map(&:first)).to include('/steps/1/when/matches')
  end

  it 'rejects a non-mapping when clause' do
    result = call(body_with('not a hash'))
    expect(result).to be_err
    expect(error_codes_and_paths(result).map(&:first)).to include('/steps/1/when')
  end

  it 'warns (does not fail) when when.artifact is not a declared artifacts key' do
    body = body_with('artifact' => 'undeclared', 'matches' => 'x')
    result = nil
    expect { result = call(body) }
      .to output(a_string_matching(/`when.artifact: undeclared` is not a declared/)).to_stderr
    expect(result).to be_ok
  end

  it 'keeps a step without when: valid (back-compat)' do
    body = {
      'id' => 'feat', 'kind' => 'task', 'artifacts' => {},
      'steps' => [
        { 'id' => 'brief', 'session_type' => 'discussion' },
        { 'id' => 'design', 'session_type' => 'discussion', 'requires' => ['brief'] }
      ]
    }
    expect(call(body)).to be_ok
  end
end
