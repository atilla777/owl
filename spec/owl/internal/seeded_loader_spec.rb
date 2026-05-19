# frozen_string_literal: true

require 'fileutils'

require_relative '../../../lib/owl/internal/seeded_loader'

RSpec.describe Owl::Internal::SeededLoader do
  def write_under(root, rel, body)
    full = File.join(root.to_s, rel)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, body)
  end

  describe '.load' do
    it 'returns relative_path + contents for every regular file, prefixed by target_prefix' do
      with_tmp_project do |root|
        write_under(root, 'skills/owl-x/SKILL.md', "x-body\n")
        write_under(root, 'skills/owl-y/SKILL.md', "y-body\n")

        result = described_class.load(source_dir: 'skills', target_prefix: '.claude/skills', repo_root: root.to_s)

        expect(result).to eq(
          [
            { relative_path: '.claude/skills/owl-x/SKILL.md', contents: "x-body\n" },
            { relative_path: '.claude/skills/owl-y/SKILL.md', contents: "y-body\n" }
          ]
        )
      end
    end

    it 'sorts files deterministically' do
      with_tmp_project do |root|
        write_under(root, 'artifacts/b/artifact.yaml', 'b')
        write_under(root, 'artifacts/a/artifact.yaml', 'a')
        write_under(root, 'artifacts/a/templates/default.md', 'a-tpl')

        result = described_class.load(source_dir: 'artifacts', target_prefix: '.owl/artifacts', repo_root: root.to_s)

        expect(result.map { |f| f[:relative_path] }).to eq(
          [
            '.owl/artifacts/a/artifact.yaml',
            '.owl/artifacts/a/templates/default.md',
            '.owl/artifacts/b/artifact.yaml'
          ]
        )
      end
    end

    it 'returns [] when source_dir does not exist' do
      with_tmp_project do |root|
        expect(described_class.load(source_dir: 'missing', target_prefix: '.owl/x', repo_root: root.to_s)).to eq([])
      end
    end

    it 'allows empty target_prefix, returning paths relative to source_dir' do
      with_tmp_project do |root|
        write_under(root, 'schemas/workflow.json', '{}')
        result = described_class.load(source_dir: 'schemas', target_prefix: '', repo_root: root.to_s)
        expect(result).to eq([{ relative_path: 'workflow.json', contents: '{}' }])
      end
    end

    it 'ignores non-file entries' do
      with_tmp_project do |root|
        write_under(root, 'skills/owl-x/SKILL.md', 'body')
        FileUtils.mkdir_p(File.join(root.to_s, 'skills', 'empty-dir'))
        result = described_class.load(source_dir: 'skills', target_prefix: '.claude/skills', repo_root: root.to_s)
        expect(result.map { |f| f[:relative_path] }).to eq(['.claude/skills/owl-x/SKILL.md'])
      end
    end
  end

  describe '.subdirectories' do
    it 'returns direct child directories sorted' do
      with_tmp_project do |root|
        write_under(root, 'artifacts/spec/artifact.yaml', '1')
        write_under(root, 'artifacts/brief/artifact.yaml', '2')
        write_under(root, 'artifacts/design/artifact.yaml', '3')

        expect(described_class.subdirectories(source_dir: 'artifacts', repo_root: root.to_s))
          .to eq(%w[brief design spec])
      end
    end

    it 'returns [] when source_dir does not exist' do
      with_tmp_project do |root|
        expect(described_class.subdirectories(source_dir: 'missing', repo_root: root.to_s)).to eq([])
      end
    end
  end
end
