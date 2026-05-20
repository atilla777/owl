# frozen_string_literal: true

require 'pathname'

require 'owl/init/api'

RSpec.describe Owl::Init::Api do
  describe '.scaffold' do
    it 'creates the canonical project layout under root and reports created paths' do
      with_tmp_project do |root|
        result = described_class.scaffold(root: root)

        expect(result).to be_ok
        value = result.value
        expect(value[:root]).to eq(root.to_s)
        expect(value[:skipped]).to eq([])
        expect(value[:created]).to include(
          "#{root}/.owl/config.yaml",
          "#{root}/.owl/workflows.yaml",
          "#{root}/.owl/artifacts.yaml",
          "#{root}/tasks/index.yaml",
          "#{root}/docs/.keep",
          "#{root}/.owl/overlays/brief.md"
        )
        %w[config.yaml workflows.yaml artifacts.yaml].each do |name|
          expect(Pathname.new("#{root}/.owl/#{name}").exist?).to be(true)
        end
      end
    end

    it 'skips existing files when --force is not set and reports them as skipped' do
      with_tmp_project do |root|
        described_class.scaffold(root: root)
        result = described_class.scaffold(root: root)

        expect(result).to be_ok
        value = result.value
        expect(value[:created]).to eq([])
        expect(value[:skipped]).to include("#{root}/.owl/config.yaml")
      end
    end

    it 'overwrites existing files when force: true' do
      with_tmp_project do |root|
        described_class.scaffold(root: root)
        Pathname.new("#{root}/.owl/config.yaml").write('# tampered')

        result = described_class.scaffold(root: root, force: true)

        expect(result).to be_ok
        value = result.value
        expect(value[:skipped]).to eq([])
        expect(value[:created]).to include("#{root}/.owl/config.yaml")
        expect(Pathname.new("#{root}/.owl/config.yaml").read).not_to eq('# tampered')
      end
    end

    it 'derives project_id from the root directory basename for config rendering' do
      with_tmp_project do |root|
        scoped = root + 'my-cool-project'
        scoped.mkpath

        result = described_class.scaffold(root: scoped)

        expect(result).to be_ok
        config_body = Pathname.new("#{scoped}/.owl/config.yaml").read
        expect(config_body).to include('my-cool-project')
      end
    end

    it 'seeds the .owl/overlays/<step>.md template with the step id in the comment header' do
      with_tmp_project do |root|
        described_class.scaffold(root: root)

        overlay_body = Pathname.new("#{root}/.owl/overlays/brief.md").read
        expect(overlay_body).to include('Optional project overlay for the `brief` step')
      end
    end
  end
end
