# frozen_string_literal: true

require 'owl/skills/api'

RSpec.describe Owl::Skills::Api do
  describe '.seeded_sources' do
    let(:sources) { described_class.seeded_sources }

    it 'returns an array of file entries with relative_path and contents' do
      expect(sources).to be_an(Array)
      expect(sources).not_to be_empty
      sources.each do |entry|
        expect(entry).to include(:relative_path, :contents)
        expect(entry[:relative_path]).to be_a(String)
        expect(entry[:contents]).to be_a(String)
      end
    end

    it 'targets `.claude/skills/` and `.claude/commands/` only' do
      sources.each do |entry|
        expect(entry[:relative_path]).to match(%r{\A\.claude/(skills|commands)/}),
                                         -> { "unexpected relative_path: #{entry[:relative_path]}" }
      end
    end

    it 'ships a top-level owl-orchestrator SKILL.md and slash-command' do
      paths = sources.map { |entry| entry[:relative_path] }
      expect(paths).to include('.claude/skills/owl-orchestrator/SKILL.md')
      expect(paths).to include('.claude/commands/owl-orchestrator.md')
    end

    it 'ships task-management slash-commands (create / status / next)' do
      paths = sources.map { |entry| entry[:relative_path] }
      expect(paths).to include('.claude/commands/owl-task-create.md')
      expect(paths).to include('.claude/commands/owl-task-status.md')
      expect(paths).to include('.claude/commands/owl-task-next.md')
    end

    it 'has unique relative paths' do
      paths = sources.map { |entry| entry[:relative_path] }
      expect(paths).to eq(paths.uniq)
    end
  end

  describe '.step_skill_ids' do
    it 'returns owl-step-<step_id> strings matching seeded workflow steps' do
      ids = described_class.step_skill_ids
      expect(ids).to all(match(/\Aowl-step-[a-z_]+\z/))
      expect(ids).not_to be_empty
    end
  end
end
