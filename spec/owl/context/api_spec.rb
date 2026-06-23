# frozen_string_literal: true

require 'owl/context/api'

RSpec.describe Owl::Context::Api do
  describe '.overlays_for' do
    it 'returns an empty list when no overlays exist' do
      with_tmp_project do |root|
        result = described_class.overlays_for(root: root, step_id: 'design')
        expect(result).to be_ok
        expect(result.value).to be_empty
      end
    end

    it 'discovers convention path .owl/overlays/<step>.md' do
      with_tmp_project do |root|
        write("#{root}/.owl/overlays/design.md", "# Project API conventions\n")
        result = described_class.overlays_for(root: root, step_id: 'design')
        expect(result.value.map { |o| o[:source] })
          .to include(end_with('.owl/overlays/design.md'))
        expect(result.value.first[:body]).to include('API conventions')
      end
    end

    it 'discovers convention path docs/ai/<step>.md' do
      with_tmp_project do |root|
        write("#{root}/docs/ai/commit_push.md", "Use conventional commits.\n")
        result = described_class.overlays_for(root: root, step_id: 'commit_push')
        expect(result.value.map { |o| o[:source] })
          .to include(end_with('docs/ai/commit_push.md'))
      end
    end

    it 'resolves session-level (non-step) overlay keys such as `orchestrator`' do
      # The `orchestrator` key is not a workflow step, but session-level overlays
      # (_owl_conventions.md §8) reuse the same convention paths so the
      # orchestrator can compose `docs/ai/orchestrator.md` into its final report.
      with_tmp_project do |root|
        write("#{root}/docs/ai/orchestrator.md", "Report must state the player-facing change.\n")
        write("#{root}/.owl/overlays/orchestrator.md", "Always finish in Russian.\n")
        result = described_class.overlays_for(root: root, step_id: 'orchestrator')
        sources = result.value.map { |o| o[:source] }
        expect(sources).to include(end_with('.owl/overlays/orchestrator.md'))
        expect(sources).to include(end_with('docs/ai/orchestrator.md'))
        expect(result.value.map { |o| o[:body] }.join).to include('player-facing change')
      end
    end

    it 'reads explicit paths from .owl/config.yaml context_overlays' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", <<~YAML)
          context_overlays:
            design:
              - docs/architecture/api-style.md
        YAML
        write("#{root}/docs/architecture/api-style.md", "Use service classes.\n")
        result = described_class.overlays_for(root: root, step_id: 'design')
        expect(result.value.map { |o| o[:source] })
          .to include(end_with('docs/architecture/api-style.md'))
      end
    end

    it 'merges convention + config sources without duplicates' do
      with_tmp_project do |root|
        write("#{root}/.owl/overlays/plan.md", "auto-discovered\n")
        write("#{root}/.owl/config.yaml", <<~YAML)
          context_overlays:
            plan:
              - .owl/overlays/plan.md
              - docs/ai/extra.md
        YAML
        write("#{root}/docs/ai/extra.md", "extra\n")
        result = described_class.overlays_for(root: root, step_id: 'plan')
        sources = result.value.map { |o| o[:source] }
        expect(sources.count { |s| s.end_with?('.owl/overlays/plan.md') }).to eq(1)
        expect(sources).to include(end_with('docs/ai/extra.md'))
      end
    end

    it 'skips empty overlay files' do
      with_tmp_project do |root|
        write("#{root}/.owl/overlays/design.md", "   \n  \n")
        result = described_class.overlays_for(root: root, step_id: 'design')
        expect(result.value).to be_empty
      end
    end

    it 'skips overlay files that contain only HTML comments (init placeholders)' do
      with_tmp_project do |root|
        write("#{root}/.owl/overlays/design.md", <<~MD)
          <!--
          Optional project overlay for the `design` step.
          -->
        MD
        result = described_class.overlays_for(root: root, step_id: 'design')
        expect(result.value).to be_empty
      end
    end

    it 'includes an overlay once non-comment content is added' do
      with_tmp_project do |root|
        write("#{root}/.owl/overlays/design.md", <<~MD)
          <!-- placeholder -->
          Use service objects for cross-domain calls.
        MD
        result = described_class.overlays_for(root: root, step_id: 'design')
        expect(result.value.first[:body]).to include('service objects')
      end
    end

    it 'flags overlays larger than the warning threshold' do
      with_tmp_project do |root|
        big = 'x' * (Owl::Context::Internal::FilesystemSource::WARNING_THRESHOLD_BYTES + 1)
        write("#{root}/.owl/overlays/design.md", big)
        result = described_class.overlays_for(root: root, step_id: 'design')
        expect(result.value.first[:warning]).to eq(:too_long)
      end
    end

    it 'tolerates malformed .owl/config.yaml' do
      with_tmp_project do |root|
        write("#{root}/.owl/config.yaml", ': : :')
        write("#{root}/.owl/overlays/design.md", "still works\n")
        result = described_class.overlays_for(root: root, step_id: 'design')
        expect(result).to be_ok
        expect(result.value.map { |o| o[:body] }).to include(include('still works'))
      end
    end

    it 'returns convention paths before explicit config paths' do
      with_tmp_project do |root|
        write("#{root}/.owl/overlays/design.md", "convention\n")
        write("#{root}/.owl/config.yaml", <<~YAML)
          context_overlays:
            design:
              - docs/ai/other.md
        YAML
        write("#{root}/docs/ai/other.md", "explicit\n")
        result = described_class.overlays_for(root: root, step_id: 'design')
        sources = result.value.map { |o| o[:source] }
        convention_idx = sources.index { |s| s.end_with?('.owl/overlays/design.md') }
        explicit_idx = sources.index { |s| s.end_with?('docs/ai/other.md') }
        expect(convention_idx).to be < explicit_idx
      end
    end
  end
end
