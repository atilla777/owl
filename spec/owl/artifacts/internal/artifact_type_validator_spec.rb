# frozen_string_literal: true

require 'owl/artifacts/internal/artifact_type_validator'

RSpec.describe Owl::Artifacts::Internal::ArtifactTypeValidator do
  def body_with_validation(validation)
    { 'id' => 'demo', 'title' => 'Demo', 'kind' => 'markdown', 'validation' => validation }
  end

  def error_paths(result)
    result.details[:errors].map { |e| e[:path] }
  end

  describe '.validate semantic validation keys' do
    it 'accepts boolean semantic keys and a placeholder array' do
      result = described_class.validate(body: body_with_validation(
        'forbid_empty_sections' => true,
        'require_scenarios' => false,
        'require_when_then' => true,
        'forbid_placeholders' => %w[TODO TBD]
      ))
      expect(result).to be_ok
    end

    it 'accepts forbid_placeholders: true' do
      result = described_class.validate(body: body_with_validation('forbid_placeholders' => true))
      expect(result).to be_ok
    end

    it 'rejects a non-boolean forbid_empty_sections' do
      result = described_class.validate(body: body_with_validation('forbid_empty_sections' => 'yes'))
      expect(result).to be_err
      expect(error_paths(result)).to include('/validation/forbid_empty_sections')
    end

    it 'rejects a non-boolean require_scenarios and require_when_then' do
      result = described_class.validate(body: body_with_validation(
        'require_scenarios' => 1,
        'require_when_then' => 'no'
      ))
      expect(error_paths(result)).to include('/validation/require_scenarios', '/validation/require_when_then')
    end

    it 'rejects forbid_placeholders that is neither boolean nor a string array' do
      result = described_class.validate(body: body_with_validation('forbid_placeholders' => 5))
      expect(error_paths(result)).to include('/validation/forbid_placeholders')
    end

    it 'rejects forbid_placeholders with blank string entries' do
      result = described_class.validate(body: body_with_validation('forbid_placeholders' => ['  ']))
      expect(error_paths(result)).to include('/validation/forbid_placeholders')
    end

    it 'leaves unknown validation keys tolerated' do
      result = described_class.validate(body: body_with_validation('some_future_key' => true))
      expect(result).to be_ok
    end
  end
end
