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

      skill_md = root + '.claude/skills/owl-orchestrator/SKILL.md'
      slash    = root + '.claude/commands/owl-orchestrator.md'
      expect(skill_md.exist?).to be(true)
      expect(slash.exist?).to be(true)
      contents = skill_md.read
      expect(contents).to include('## Stop Conditions')
      expect(contents).to include('owl-step-discussion')
      expect(contents).to include('owl-step-execution')
    end
  end

  it 'materializes the owl-cli skill + slash-command in .claude/' do
    with_tmp_project do |root|
      exit_code, _stdout, _stderr = run(['init', '--root', root.to_s], cwd: root)
      expect(exit_code).to eq(0)

      skill_md = root + '.claude/skills/owl-cli/SKILL.md'
      slash    = root + '.claude/commands/owl-cli.md'
      expect(skill_md.exist?).to be(true)
      expect(slash.exist?).to be(true)
      expect(skill_md.read).to include('## CLI Usage')
      expect(skill_md.read).to include('## Canonical Operations')
    end
  end

  it 'materializes the owl-step-discussion skill + slash-command in .claude/' do
    with_tmp_project do |root|
      exit_code, _stdout, _stderr = run(['init', '--root', root.to_s], cwd: root)
      expect(exit_code).to eq(0)

      skill_md = root + '.claude/skills/owl-step-discussion/SKILL.md'
      slash    = root + '.claude/commands/owl-step-discussion.md'
      expect(skill_md.exist?).to be(true)
      expect(slash.exist?).to be(true)
      expect(skill_md.read).to include('## Workflow')
      expect(skill_md.read).to include('owl step show')
    end
  end

  it 'materializes the owl-step-execution skill + slash-command in .claude/' do
    with_tmp_project do |root|
      exit_code, _stdout, _stderr = run(['init', '--root', root.to_s], cwd: root)
      expect(exit_code).to eq(0)

      skill_md = root + '.claude/skills/owl-step-execution/SKILL.md'
      slash    = root + '.claude/commands/owl-step-execution.md'
      expect(skill_md.exist?).to be(true)
      expect(slash.exist?).to be(true)
      expect(skill_md.read).to include('## Workflow')
      expect(skill_md.read).to include('owl step report')
    end
  end

  it 'materializes the owl-init skill + slash-command in .claude/' do
    with_tmp_project do |root|
      exit_code, _stdout, _stderr = run(['init', '--root', root.to_s], cwd: root)
      expect(exit_code).to eq(0)

      skill_md = root + '.claude/skills/owl-init/SKILL.md'
      slash    = root + '.claude/commands/owl-init.md'
      expect(skill_md.exist?).to be(true)
      expect(slash.exist?).to be(true)
      expect(skill_md.read).to include('## Workflow')
      expect(skill_md.read).to include('owl config set settings.language.communication')
      expect(skill_md.read).to include('## Language Clause')
    end
  end

  it 'materializes the owl-author skill + slash-command in .claude/' do
    with_tmp_project do |root|
      exit_code, _stdout, _stderr = run(['init', '--root', root.to_s], cwd: root)
      expect(exit_code).to eq(0)

      skill_md = root + '.claude/skills/owl-author/SKILL.md'
      slash    = root + '.claude/commands/owl-author.md'
      expect(skill_md.exist?).to be(true)
      expect(slash.exist?).to be(true)
      expect(skill_md.read).to include('Mode A — Create workflow')
      expect(skill_md.read).to include('Mode B — Create artifact-type')
      expect(skill_md.read).to include('Mode C — Edit existing')
    end
  end

  it 'materializes only the universal owl-* skills (no per-step owl-step-<id> skills)' do
    with_tmp_project do |root|
      run(['init', '--root', root.to_s], cwd: root)

      step_skill_files = Dir[(root + '.claude/skills/owl-*/SKILL.md').to_s]
      expect(step_skill_files.map { |f| File.basename(File.dirname(f)) }).to contain_exactly(
        'owl-cli',
        'owl-step-discussion',
        'owl-step-execution',
        'owl-orchestrator',
        'owl-init',
        'owl-author'
      )
    end
  end

  it 'materializes per-step .context.md files under .owl/workflows/<wf>/' do
    with_tmp_project do |root|
      run(['init', '--root', root.to_s], cwd: root)

      context_files = Dir[(root + '.owl/workflows/**/*.context.md').to_s]
      expect(context_files).not_to be_empty
      # 5 workflows: feature(7 non-brief steps + 3 brief variants = 10) +
      #   composite_feature(5 non-brief steps + 3 brief variants = 8) +
      #   hotfix(lean: implement + review_code + commit_push + 3 brief variants = 6) +
      #   refactor(10) + quick(brief + implement + commit_push = 3)
      #   = 37 step contexts.
      expect(context_files.size).to eq(37)
    end
  end

  it 'materializes the eleven universal owl-* slash-commands (6 skills + 3 owl-task-* + owl-workflow-show + owl-overview)' do
    with_tmp_project do |root|
      run(['init', '--root', root.to_s], cwd: root)

      command_files = Dir[(root + '.claude/commands/owl-*.md').to_s]
      expect(command_files.map { |f| File.basename(f, '.md') }).to contain_exactly(
        'owl-orchestrator',
        'owl-cli',
        'owl-step-discussion',
        'owl-step-execution',
        'owl-init',
        'owl-author',
        'owl-task-create',
        'owl-task-status',
        'owl-task-next',
        'owl-workflow-show',
        'owl-overview'
      )
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
      # Seed bodies (.claude/*) are refreshed by --force; user state (config,
      # registries, index) and project overlays are preserved (skipped).
      expect(body['skipped']).to include(a_string_ending_with('/.owl/config.yaml'))
      expect(target.read).not_to eq("# mutated by the test\n")
    end
  end

  it 'materializes the OpenCode layout with --agent opencode' do
    with_tmp_project do |root|
      exit_code, _stdout, _stderr = run(['init', '--root', root.to_s, '--agent', 'opencode'], cwd: root)
      expect(exit_code).to eq(0)

      expect((root + '.opencode/skills/owl-orchestrator/SKILL.md').exist?).to be(true)
      expect((root + '.opencode/commands/owl-orchestrator.md').exist?).to be(true)
      expect((root + '.claude').exist?).to be(false)
    end
  end

  it 'materializes both layouts with --agent both' do
    with_tmp_project do |root|
      exit_code, _stdout, _stderr = run(['init', '--root', root.to_s, '--agent', 'both'], cwd: root)
      expect(exit_code).to eq(0)

      expect((root + '.claude/skills/owl-cli/SKILL.md').exist?).to be(true)
      expect((root + '.opencode/skills/owl-cli/SKILL.md').exist?).to be(true)
    end
  end

  it 'rejects an unsupported --agent value' do
    with_tmp_project do |root|
      exit_code, _stdout, stderr = run(['init', '--root', root.to_s, '--agent', 'cursor'], cwd: root)
      expect(exit_code).not_to eq(0)
      body = JSON.parse(stderr)
      expect(body['error']['code']).to eq('invalid_arguments')
    end
  end
end
