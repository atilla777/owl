# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'

SEEDED_WORKFLOW_KEYS = %w[feature composite_feature feature_slice hotfix research refactor].freeze
SEEDED_ARTIFACT_KEYS = %w[
  brief design plan review spec tasks
  decomposition verification issue patch_plan
  research_findings recommendation
].freeze

RSpec.describe 'owl init seeded workflow + artifact templates' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  it 'materializes a workflow.yaml for each of the six workflow types' do
    with_tmp_project do |root|
      run(['init', '--root', root.to_s], cwd: root)

      SEEDED_WORKFLOW_KEYS.each do |key|
        path = root + ".owl/workflows/#{key}/workflow.yaml"
        expect(path.exist?).to be(true), "missing workflow source for #{key}"

        parsed = YAML.safe_load(path.read)
        expect(parsed['id']).to eq(key)
        expect(parsed['steps']).to be_an(Array).and(satisfy('non-empty') { |s| !s.empty? })
        expect(parsed['artifacts']).to be_a(Hash)
      end
    end
  end

  it 'materializes an artifact.yaml + templates/default.md for each of the twelve artifact types' do
    with_tmp_project do |root|
      run(['init', '--root', root.to_s], cwd: root)

      SEEDED_ARTIFACT_KEYS.each do |key|
        artifact_yaml = root + ".owl/artifacts/#{key}/artifact.yaml"
        template_md = root + ".owl/artifacts/#{key}/templates/default.md"

        expect(artifact_yaml.exist?).to be(true), "missing artifact YAML for #{key}"
        expect(template_md.exist?).to be(true), "missing default template for #{key}"

        parsed = YAML.safe_load(artifact_yaml.read)
        expect(parsed['id']).to eq(key)
        expect(parsed['kind']).to eq('markdown')
        expect(parsed['default_template']).to eq('templates/default.md')
        expect(parsed.dig('validation', 'required_sections')).to be_an(Array)
      end
    end
  end

  describe 'owl config validate --json' do
    it 'returns valid: true with all six workflows + twelve artifacts on a fresh init' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        exit_code, stdout, _stderr = run(['config', 'validate', '--root', root.to_s, '--json'], cwd: root)
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['valid']).to be(true)
        expect(body.dig('workflows', 'count')).to eq(6)
        expect(body.dig('workflows', 'keys')).to match_array(SEEDED_WORKFLOW_KEYS)
        expect(body.dig('artifacts', 'count')).to eq(12)
        expect(body.dig('artifacts', 'keys')).to match_array(SEEDED_ARTIFACT_KEYS)
        expect(body['errors']).to eq([])
      end
    end
  end

  describe 'owl task create per seeded workflow' do
    SEEDED_WORKFLOW_KEYS.each do |workflow_key|
      it "creates a task on the '#{workflow_key}' workflow with every step in pending status" do
        with_tmp_project do |root|
          run(['init', '--root', root.to_s], cwd: root)
          exit_code, stdout, _stderr = run(
            ['task', 'create', '--workflow', workflow_key, '--title', 'sample',
             '--root', root.to_s, '--json'],
            cwd: root
          )
          expect(exit_code).to eq(0), "task create failed for #{workflow_key}: #{stdout}"

          body = JSON.parse(stdout)
          expect(body['ok']).to be(true)
          expect(body.dig('task', 'workflow', 'key')).to eq(workflow_key)
          statuses = body.dig('task', 'steps').map { |s| s['status'] }
          expect(statuses).to all(eq('pending'))
          expect(statuses).not_to be_empty
        end
      end
    end
  end

  describe 'owl task ready-steps on the seeded feature workflow' do
    it 'returns the initial ready set after task create on feature' do
      with_tmp_project do |root|
        run(['init', '--root', root.to_s], cwd: root)
        _exit, stdout, _stderr = run(
          ['task', 'create', '--workflow', 'feature', '--title', 't',
           '--root', root.to_s, '--json'],
          cwd: root
        )
        task_id = JSON.parse(stdout).dig('task', 'id')

        exit_code, stdout, _stderr = run(
          ['task', 'ready-steps', task_id, '--root', root.to_s, '--json'],
          cwd: root
        )
        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body['ok']).to be(true)
        expect(body['ready'].map { |s| s['id'] }).to eq(['brief'])
      end
    end
  end
end
