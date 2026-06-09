# frozen_string_literal: true

require 'pathname'

require 'owl/init/api'
require 'owl/config/api'

RSpec.describe Owl::Init::Api do
  def agent_targets_in(root)
    Owl::Config::Api.read_key(root: root.to_s, key: 'settings.agent_targets').value[:value]
  end

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
        # only the preserve-on-force overlays are skipped; everything else is overwritten
        expect(value[:skipped]).to all(include('/.owl/overlays/'))
        expect(value[:created]).to include("#{root}/.owl/config.yaml")
        expect(Pathname.new("#{root}/.owl/config.yaml").read).not_to eq('# tampered')
      end
    end

    it 'preserves customized overlay files on a forced re-run instead of clobbering them' do
      with_tmp_project do |root|
        described_class.scaffold(root: root)
        overlay = Pathname.new("#{root}/.owl/overlays/commit_push.md")
        overlay.write('# project-authored overlay content')

        result = described_class.scaffold(root: root, force: true)

        expect(result).to be_ok
        value = result.value
        expect(value[:skipped]).to include(overlay.to_s)
        expect(value[:created]).not_to include(overlay.to_s)
        expect(overlay.read).to eq('# project-authored overlay content')
        # non-overlay files are still overwritten by --force
        expect(value[:created]).to include("#{root}/.owl/config.yaml")
      end
    end

    it 'still seeds overlay files on a forced re-run when they are missing' do
      with_tmp_project do |root|
        described_class.scaffold(root: root)
        Pathname.new("#{root}/.owl/overlays/commit_push.md").delete

        result = described_class.scaffold(root: root, force: true)

        expect(result).to be_ok
        expect(result.value[:created]).to include("#{root}/.owl/overlays/commit_push.md")
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

    context 'with agent_targets' do
      it 'defaults to the Claude Code layout and records it in settings.agent_targets' do
        with_tmp_project do |root|
          described_class.scaffold(root: root)

          expect(Pathname.new("#{root}/.claude/skills/owl-orchestrator/SKILL.md").exist?).to be(true)
          expect(Pathname.new("#{root}/.opencode").exist?).to be(false)
          expect(agent_targets_in(root)).to eq(%w[claude])
        end
      end

      it 'materializes the OpenCode layout and records it when agent_targets: [:opencode]' do
        with_tmp_project do |root|
          described_class.scaffold(root: root, agent_targets: %i[opencode])

          expect(Pathname.new("#{root}/.opencode/skills/owl-orchestrator/SKILL.md").exist?).to be(true)
          expect(Pathname.new("#{root}/.opencode/commands/owl-orchestrator.md").exist?).to be(true)
          expect(Pathname.new("#{root}/.claude").exist?).to be(false)
          expect(agent_targets_in(root)).to eq(%w[opencode])
        end
      end

      it 'materializes both layouts when agent_targets: [:claude, :opencode]' do
        with_tmp_project do |root|
          described_class.scaffold(root: root, agent_targets: %i[claude opencode])

          expect(Pathname.new("#{root}/.claude/skills/owl-cli/SKILL.md").exist?).to be(true)
          expect(Pathname.new("#{root}/.opencode/skills/owl-cli/SKILL.md").exist?).to be(true)
          expect(agent_targets_in(root)).to eq(%w[claude opencode])
        end
      end

      it 'honours the persisted target on a forced re-run with no explicit agent_targets' do
        with_tmp_project do |root|
          described_class.scaffold(root: root, agent_targets: %i[opencode])
          described_class.scaffold(root: root, force: true)

          expect(agent_targets_in(root)).to eq(%w[opencode])
        end
      end
    end
  end
end
