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

  def make_self_hosted(root)
    write("#{root}/owl-cli.gemspec", "# gemspec\n")
    write("#{root}/lib/owl/version.rb", "module Owl; VERSION = '0.0.0'; end\n")
  end

  describe '.info' do
    context 'in a consumer project (not self-hosted)' do
      it 'reports self_hosted: false and up_to_date: true when the stamp matches the gem' do
        with_tmp_project do |root|
          write_config_with_owl_version(root, Owl::VERSION)

          result = described_class.info(root: root)

          expect(result).to be_ok
          expect(result.value).to eq(gem: Owl::VERSION, project: Owl::VERSION, self_hosted: false, up_to_date: true)
        end
      end

      it 'reports drift (up_to_date: false) when the stamped version differs from the gem' do
        with_tmp_project do |root|
          write_config_with_owl_version(root, '0.0.1')

          result = described_class.info(root: root)

          expect(result).to be_ok
          expect(result.value).to eq(gem: Owl::VERSION, project: '0.0.1', self_hosted: false, up_to_date: false)
        end
      end

      it 'returns project: nil and up_to_date: false for a legacy project without owl.version' do
        with_tmp_project do |root|
          write_legacy_config(root)

          result = described_class.info(root: root)

          expect(result).to be_ok
          expect(result.value).to eq(gem: Owl::VERSION, project: nil, self_hosted: false, up_to_date: false)
        end
      end
    end

    context 'in the self-hosted source repository' do
      it 'treats Owl::VERSION as authoritative and reports up_to_date even with a stale stamp' do
        with_tmp_project do |root|
          write_config_with_owl_version(root, '0.0.1')
          make_self_hosted(root)

          result = described_class.info(root: root)

          expect(result).to be_ok
          expect(result.value).to eq(
            gem: Owl::VERSION, project: Owl::VERSION, self_hosted: true, up_to_date: true
          )
        end
      end

      it 'does not write to .owl/config.yaml (the stale stamp is left untouched)' do
        with_tmp_project do |root|
          write_config_with_owl_version(root, '0.0.1')
          make_self_hosted(root)

          described_class.info(root: root)

          expect((root / '.owl' / 'config.yaml').read).to include("version: '0.0.1'")
        end
      end
    end
  end
end
