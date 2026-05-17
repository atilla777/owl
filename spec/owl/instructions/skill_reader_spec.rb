# frozen_string_literal: true

require 'owl/instructions/api'

RSpec.describe 'Owl::Instructions::Api.read_skill' do
  def write_skill(root, skill_id, body)
    write("#{root}/.claude/skills/#{skill_id}/SKILL.md", body)
  end

  def write_command(root, skill_id, body)
    write("#{root}/.claude/commands/#{skill_id}.md", body)
  end

  it 'returns skill path, command_path and the first non-heading paragraph as summary' do
    with_tmp_project do |root|
      write_skill(root, 'owl-step-foo', <<~MD)
        ---
        name: owl-step-foo
        description: Foo skill.
        ---

        Foo step does foo work. Triggered when bar.

        ## Purpose

        Some purpose text.
      MD
      write_command(root, 'owl-step-foo', "# command\n")

      result = Owl::Instructions::Api.read_skill(root: root, skill_id: 'owl-step-foo')
      expect(result.ok?).to be(true)
      expect(result.value[:skill][:id]).to eq('owl-step-foo')
      expect(result.value[:skill][:path]).to end_with('.claude/skills/owl-step-foo/SKILL.md')
      expect(result.value[:skill][:command_path]).to end_with('.claude/commands/owl-step-foo.md')
      expect(result.value[:summary]).to eq('Foo step does foo work. Triggered when bar.')
    end
  end

  it 'returns nil command_path when the slash-command file is absent' do
    with_tmp_project do |root|
      write_skill(root, 'owl-step-bar', "---\nname: owl-step-bar\n---\n\nBody text.\n")

      result = Owl::Instructions::Api.read_skill(root: root, skill_id: 'owl-step-bar')
      expect(result.ok?).to be(true)
      expect(result.value[:skill][:command_path]).to be_nil
    end
  end

  it 'returns empty summary when SKILL.md only has front-matter and headings' do
    with_tmp_project do |root|
      write_skill(root, 'owl-step-empty', <<~MD)
        ---
        name: owl-step-empty
        ---

        ## Purpose

        ## When to use
      MD

      result = Owl::Instructions::Api.read_skill(root: root, skill_id: 'owl-step-empty')
      expect(result.ok?).to be(true)
      expect(result.value[:summary]).to eq('')
    end
  end

  it 'returns :skill_not_found when SKILL.md does not exist' do
    with_tmp_project do |root|
      result = Owl::Instructions::Api.read_skill(root: root, skill_id: 'owl-step-missing')
      expect(result.err?).to be(true)
      expect(result.code).to eq(:skill_not_found)
    end
  end
end
