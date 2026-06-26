# frozen_string_literal: true

require 'owl/version/api'

RSpec.describe Owl::Version::Api do
  def write_config_with_owl_version(root, version)
    write("#{root}/.owl/config.yaml", <<~YAML)
      schema_version: 1
      project:
        id: sample
      owl:
        control_root: "/tmp/.owl"
        version: '#{version}'
    YAML
  end

  def write_legacy_config(root)
    write("#{root}/.owl/config.yaml", <<~YAML)
      schema_version: 1
      project:
        id: sample
      owl:
        control_root: "/tmp/.owl"
    YAML
  end

  describe '.info' do
    it 'reports up_to_date: true when the stamped version matches the gem' do
      with_tmp_project do |root|
        write_config_with_owl_version(root, Owl::VERSION)

        result = described_class.info(root: root)

        expect(result).to be_ok
        expect(result.value).to eq(gem: Owl::VERSION, project: Owl::VERSION, up_to_date: true)
      end
    end

    it 'reports drift (up_to_date: false) when the stamped version differs from the gem' do
      with_tmp_project do |root|
        write_config_with_owl_version(root, '0.0.1')

        result = described_class.info(root: root)

        expect(result).to be_ok
        expect(result.value).to eq(gem: Owl::VERSION, project: '0.0.1', up_to_date: false)
      end
    end

    it 'returns project: nil and up_to_date: false for a legacy project without owl.version' do
      with_tmp_project do |root|
        write_legacy_config(root)

        result = described_class.info(root: root)

        expect(result).to be_ok
        expect(result.value).to eq(gem: Owl::VERSION, project: nil, up_to_date: false)
      end
    end
  end
end
