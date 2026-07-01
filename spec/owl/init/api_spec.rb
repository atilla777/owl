# frozen_string_literal: true

require 'pathname'

require 'owl/init/api'
require 'owl/config/api'

RSpec.describe Owl::Init::Api do
  def agent_targets_in(root)
    Owl::Config::Api.read_key(root: root.to_s, key: 'settings.agent_targets').value[:value]
  end

  def stamped_version_in(root)
    Owl::Config::Api.read_key(root: root.to_s, key: 'owl.version').value[:value]
  end

  describe '.scaffold' do
    it 'stamps owl.version with the running Owl::VERSION (regression: sync on init)' do
      with_tmp_project do |root|
        described_class.scaffold(root: root)

        expect(stamped_version_in(root)).to eq(Owl::VERSION)
      end
    end

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
          "#{root}/.owl/overlays/brief.md",
          "#{root}/.owl/overlays/orchestrator.md"
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

    it 'refreshes seed bodies but preserves user config settings on force: true' do
      with_tmp_project do |root|
        described_class.scaffold(root: root)
        # A real user customization (not garbage) so the config stays valid for
        # the version/agent-target stamping that follows the scaffold.
        Owl::Config::Api.write_key(root: root.to_s, key: 'settings.language.communication', value: 'ru')
        skill = Pathname.new("#{root}/.claude/skills/owl-orchestrator/SKILL.md")
        skill.write('# tampered skill')

        result = described_class.scaffold(root: root, force: true)

        expect(result).to be_ok
        value = result.value
        # Config is preserved by the scaffolder (skipped), so the user setting
        # survives; the materialised skill body is refreshed.
        expect(value[:skipped]).to include("#{root}/.owl/config.yaml")
        expect(value[:created]).not_to include("#{root}/.owl/config.yaml")
        expect(
          Owl::Config::Api.read_key(root: root.to_s, key: 'settings.language.communication').value[:value]
        ).to eq('ru')
        expect(value[:created]).to include(skill.to_s)
        expect(skill.read).not_to eq('# tampered skill')
      end
    end

    it 'preserves the registries and the task index verbatim on a forced re-run' do
      with_tmp_project do |root|
        described_class.scaffold(root: root)
        # These files are never touched by the post-scaffold version/target
        # stamping, so they stay byte-identical across a forced re-run.
        state = {
          "#{root}/.owl/workflows.yaml" => "# my workflows registry\n",
          "#{root}/.owl/artifacts.yaml" => "# my artifacts registry\n",
          "#{root}/tasks/index.yaml" => "# my index\n"
        }
        state.each { |path, body| Pathname.new(path).write(body) }

        result = described_class.scaffold(root: root, force: true)

        expect(result).to be_ok
        state.each do |path, body|
          expect(result.value[:skipped]).to include(path)
          expect(Pathname.new(path).read).to eq(body)
        end
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

    it 'seeds a generic overlay template with the step id in the comment header' do
      with_tmp_project do |root|
        described_class.scaffold(root: root)

        overlay_body = Pathname.new("#{root}/.owl/overlays/design.md").read
        expect(overlay_body).to include('Optional project overlay for the `design` step')
      end
    end

    it 'seeds an active completeness checklist for the brief overlay (not a commented-out stub)' do
      with_tmp_project do |root|
        described_class.scaffold(root: root)

        overlay_body = Pathname.new("#{root}/.owl/overlays/brief.md").read
        expect(overlay_body).to include('Brief completeness checklist')
        expect(overlay_body).not_to include('Optional project overlay for the `brief` step')
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
