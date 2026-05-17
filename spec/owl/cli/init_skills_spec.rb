# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/cli/api'

RSpec.describe 'owl init — Owl::Skills integration' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  it 'materializes the owl-orchestrator skill + slash-command in .claude/' do
    with_tmp_project do |root|
      exit_code, _stdout, _stderr = run(['init', '--root', root.to_s], cwd: root)
      expect(exit_code).to eq(0)

      expect((root + '.claude/skills/owl-orchestrator/SKILL.md').exist?).to be(true)
      expect((root + '.claude/commands/owl-orchestrator.md').exist?).to be(true)
    end
  end

  it 'materializes every owl-step-<id> skill (≥ 17 step skills)' do
    with_tmp_project do |root|
      run(['init', '--root', root.to_s], cwd: root)

      step_skill_files = Dir[(root + '.claude/skills/owl-step-*/SKILL.md').to_s]
      expect(step_skill_files.size).to be >= 17
    end
  end

  it 'materializes ≥ 20 owl-* slash-commands (steps + orchestrator + task-management)' do
    with_tmp_project do |root|
      run(['init', '--root', root.to_s], cwd: root)

      command_files = Dir[(root + '.claude/commands/owl-*.md').to_s]
      expect(command_files.size).to be >= 20
    end
  end

  it 'skips existing .claude/ files without --force on a re-run' do
    with_tmp_project do |root|
      run(['init', '--root', root.to_s], cwd: root)
      _exit, stdout, _stderr = run(['init', '--root', root.to_s], cwd: root)

      body = JSON.parse(stdout)
      expect(body['created']).to eq([])
      expect(body['skipped']).to include(
        a_string_ending_with('.claude/skills/owl-orchestrator/SKILL.md'),
        a_string_ending_with('.claude/commands/owl-orchestrator.md')
      )
    end
  end

  it 'rewrites existing .claude/ files with --force' do
    with_tmp_project do |root|
      run(['init', '--root', root.to_s], cwd: root)
      target = root + '.claude/skills/owl-orchestrator/SKILL.md'
      target.write("# mutated by the test\n")

      _exit, stdout, _stderr = run(['init', '--root', root.to_s, '--force'], cwd: root)

      body = JSON.parse(stdout)
      expect(body['created']).to include(target.to_s)
      expect(body['skipped']).to eq([])
      expect(target.read).not_to eq("# mutated by the test\n")
    end
  end
end
