# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/tasks/api'
require 'owl/steps/api'
require 'owl/workflows/api'

RSpec.describe Owl::Workflows::Api, '.ready_steps conditional when: gate' do
  def run_cli(argv, root)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv + ['--root', root.to_s], stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s)
    [stdout.string, stderr.string]
  end

  def write_brief_artifact_registry(root)
    write("#{root}/.owl/artifacts.yaml", <<~YAML)
      schema_version: 1
      artifacts:
        brief:
          source: "artifacts/brief/artifact.yaml"
    YAML
    write("#{root}/.owl/artifacts/brief/artifact.yaml", <<~YAML)
      id: brief
      kind: markdown
      default_template: templates/default.md
    YAML
    write("#{root}/.owl/artifacts/brief/templates/default.md", "# Brief\n")
  end

  # Workflow: brief (creates brief) -> design (when: matches/not_matches over brief)
  #           -> plan (requires design).
  def seed(root, when_clause)
    run_cli(['init'], root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feat:
          enabled: true
          source: "workflows/feat/workflow.yaml"
    YAML
    write_brief_artifact_registry(root)
    design_step = { 'id' => 'design', 'session_type' => 'discussion', 'requires' => ['brief'] }
    design_step['when'] = when_clause if when_clause
    body = {
      'id' => 'feat', 'kind' => 'task',
      'artifacts' => { 'brief' => { 'type' => 'brief',
                                    'storage' => { 'role' => 'tasks', 'path' => '{{task.id}}/brief.md' } } },
      'steps' => [
        { 'id' => 'brief', 'session_type' => 'discussion', 'creates' => ['brief'] },
        design_step,
        { 'id' => 'plan', 'session_type' => 'execution', 'requires' => ['design'] }
      ]
    }
    write("#{root}/.owl/workflows/feat/workflow.yaml", YAML.dump(body))
    run_cli(['task', 'create', '--workflow', 'feat', '--title', 't'], root)
    'TASK-0001'
  end

  def complete_brief(root, task_id, body)
    write("#{root}/tasks/#{task_id}/brief.md", body)
    Owl::Steps::Api.start(root: root, task_id: task_id, step_id: 'brief')
    Owl::Steps::Api.complete(root: root, task_id: task_id, step_id: 'brief')
  end

  let(:matches_design) { { 'artifact' => 'brief', 'matches' => 'needs design' } }
  let(:not_matches_skip) { { 'artifact' => 'brief', 'not_matches' => 'SKIP-DESIGN' } }

  it 'keeps design ready when the matches predicate is true' do
    with_tmp_project do |root|
      task_id = seed(root, matches_design)
      complete_brief(root, task_id, "# Brief\n\nThis feature needs design work.\n")

      result = described_class.ready_steps(root: root, task_id: task_id)
      expect(result).to be_ok
      expect(result.value[:ready].map { |s| s[:id] }).to eq(['design'])
      expect(result.value[:conditional_skip]).to eq([])
    end
  end

  it 'moves design into conditional_skip when the matches predicate is false' do
    with_tmp_project do |root|
      task_id = seed(root, matches_design)
      complete_brief(root, task_id, "# Brief\n\nA trivial change, no design needed.\n")

      result = described_class.ready_steps(root: root, task_id: task_id)
      expect(result).to be_ok
      expect(result.value[:ready].map { |s| s[:id] }).not_to include('design')
      expect(result.value[:conditional_skip]).to eq([{ id: 'design', reason: 'condition_unmet' }])
    end
  end

  it 'unblocks the dependent step once the conditional step is skipped' do
    with_tmp_project do |root|
      task_id = seed(root, matches_design)
      complete_brief(root, task_id, "# Brief\n\nNo design needed.\n")
      Owl::Steps::Api.skip(root: root, task_id: task_id, step_id: 'design', reason: 'condition_unmet')

      result = described_class.ready_steps(root: root, task_id: task_id)
      expect(result.value[:ready].map { |s| s[:id] }).to eq(['plan'])
      expect(result.value[:conditional_skip]).to eq([])
    end
  end

  it 'supports the not_matches operator (true → ready)' do
    with_tmp_project do |root|
      task_id = seed(root, not_matches_skip)
      complete_brief(root, task_id, "# Brief\n\nNormal feature.\n")

      result = described_class.ready_steps(root: root, task_id: task_id)
      expect(result.value[:ready].map { |s| s[:id] }).to eq(['design'])
      expect(result.value[:conditional_skip]).to eq([])
    end
  end

  it 'supports the not_matches operator (matching body → conditional_skip)' do
    with_tmp_project do |root|
      task_id = seed(root, not_matches_skip)
      complete_brief(root, task_id, "# Brief\n\nSKIP-DESIGN: trivial.\n")

      result = described_class.ready_steps(root: root, task_id: task_id)
      expect(result.value[:conditional_skip]).to eq([{ id: 'design', reason: 'condition_unmet' }])
    end
  end

  it 'treats a missing predicate artifact as condition-unmet (safe default skip)' do
    with_tmp_project do |root|
      # Point the predicate at a brief that is never written.
      task_id = seed(root, matches_design)
      # Mark brief done WITHOUT writing the artifact file is impossible (complete
      # validates output), so instead delete the file after completion.
      complete_brief(root, task_id, "# Brief\n\nneeds design\n")
      File.delete("#{root}/tasks/#{task_id}/brief.md")

      result = described_class.ready_steps(root: root, task_id: task_id)
      expect(result.value[:conditional_skip]).to eq([{ id: 'design', reason: 'condition_unmet' }])
    end
  end

  it 'surfaces the conditional_skip bucket through the `owl task ready-steps` CLI' do
    with_tmp_project do |root|
      task_id = seed(root, matches_design)
      complete_brief(root, task_id, "# Brief\n\nNo design needed.\n")

      stdout, = run_cli(['task', 'ready-steps', task_id, '--json'], root)
      payload = JSON.parse(stdout)
      expect(payload['conditional_skip']).to eq([{ 'id' => 'design', 'reason' => 'condition_unmet' }])
      expect(payload['ready'].map { |s| s['id'] }).not_to include('design')
    end
  end

  it 'leaves a step without when: unchanged (back-compat)' do
    with_tmp_project do |root|
      task_id = seed(root, nil) # no when clause
      complete_brief(root, task_id, "# Brief\n\nanything\n")

      result = described_class.ready_steps(root: root, task_id: task_id)
      expect(result.value[:ready].map { |s| s[:id] }).to eq(['design'])
      expect(result.value[:conditional_skip]).to eq([])
    end
  end
end
