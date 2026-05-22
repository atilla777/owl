# frozen_string_literal: true

require 'owl/subagents/internal/tier_map'

RSpec.describe Owl::Subagents::Internal::TierMap do
  let(:valid_yaml) do
    <<~YAML
      schema_version: 1
      tier_map:
        standard: sonnet-x
        advanced: opus-x
    YAML
  end

  it 'resolves a tier using OWL_TIER_MAP_PATH env var' do
    with_tmp_project do |root|
      path = "#{root}/tier_map.yaml"
      write(path, valid_yaml)
      result = described_class.resolve('advanced', env: { 'OWL_TIER_MAP_PATH' => path })
      expect(result).to eq('opus-x')
    end
  end

  it 'resolves a tier using an explicit config_path argument' do
    with_tmp_project do |root|
      path = "#{root}/tier_map.yaml"
      write(path, valid_yaml)
      result = described_class.resolve('standard', env: {}, config_path: path)
      expect(result).to eq('sonnet-x')
    end
  end

  it 'falls back to ~/.config/owl/tier_map.yaml when env var unset' do
    with_tmp_project do |root|
      path = "#{root}/tier_map.yaml"
      write(path, valid_yaml)
      # Simulate the default-path code path by passing an empty env
      # but having config_path point at the default location.
      allow(File).to receive(:expand_path).with(described_class::DEFAULT_CONFIG_PATH).and_return(path)
      result = described_class.resolve('standard', env: {})
      expect(result).to eq('sonnet-x')
    end
  end

  it 'treats an empty OWL_TIER_MAP_PATH env var as unset and falls back' do
    with_tmp_project do |root|
      path = "#{root}/tier_map.yaml"
      write(path, valid_yaml)
      allow(File).to receive(:expand_path).with(described_class::DEFAULT_CONFIG_PATH).and_return(path)
      result = described_class.resolve('standard', env: { 'OWL_TIER_MAP_PATH' => '' })
      expect(result).to eq('sonnet-x')
    end
  end

  it 'raises ConfigMissing when the resolved path does not exist' do
    with_tmp_project do |root|
      missing = "#{root}/missing.yaml"
      expect do
        described_class.resolve('standard', env: { 'OWL_TIER_MAP_PATH' => missing })
      end.to raise_error(described_class::ConfigMissing, /tier_map config not found/)
    end
  end

  it 'raises MalformedConfig when YAML root is not a mapping' do
    with_tmp_project do |root|
      path = "#{root}/tier_map.yaml"
      write(path, "- a\n- b\n")
      expect do
        described_class.resolve('standard', env: { 'OWL_TIER_MAP_PATH' => path })
      end.to raise_error(described_class::MalformedConfig, /must be a YAML mapping/)
    end
  end

  it 'raises MalformedConfig when `tier_map` key is missing or not a mapping' do
    with_tmp_project do |root|
      path = "#{root}/tier_map.yaml"
      write(path, "schema_version: 1\ntier_map: \"oops\"\n")
      expect do
        described_class.resolve('standard', env: { 'OWL_TIER_MAP_PATH' => path })
      end.to raise_error(described_class::MalformedConfig, /must contain a `tier_map:` mapping/)
    end
  end

  it 'raises MalformedConfig on invalid YAML syntax' do
    with_tmp_project do |root|
      path = "#{root}/tier_map.yaml"
      write(path, ':: :: :')
      expect do
        described_class.resolve('standard', env: { 'OWL_TIER_MAP_PATH' => path })
      end.to raise_error(described_class::MalformedConfig, /is invalid/)
    end
  end

  it 'raises UnknownTier when tier name not present in mapping' do
    with_tmp_project do |root|
      path = "#{root}/tier_map.yaml"
      write(path, valid_yaml)
      expect do
        described_class.resolve('experimental', env: { 'OWL_TIER_MAP_PATH' => path })
      end.to raise_error(described_class::UnknownTier, /not declared/)
    end
  end
end
