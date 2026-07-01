# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/cli/api'

# TASK-0009: the refactor workflow declares the optional `spec_delta` artifact
# (parity with feature, TASK-0007) without adding a creating step, and still
# validates end-to-end with its 8-step graph unchanged. (v1.6.0: `hotfix` was
# trimmed to a lean 4-step flow and no longer carries spec_delta — see the
# separate lean-hotfix describe below.)
RSpec.describe 'refactor declares the optional spec_delta artifact' do
  def repo_root
    Pathname.new(File.expand_path('../../..', __dir__))
  end

  def expected_step_ids
    %w[brief design plan implement review_code merge_docs archive commit_push]
  end

  def run_cli(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    stdout.string
  end

  def workflow_body(name)
    YAML.safe_load(repo_root.join('.owl', 'workflows', name, 'workflow.yaml').read)
  end

  describe 'refactor' do
    it 'validates with valid:true' do
      body = JSON.parse(run_cli(['workflow', 'validate', 'refactor', '--json'], cwd: repo_root))
      expect(body).to include('ok' => true, 'valid' => true, 'id' => 'refactor')
    end

    it 'keeps the 8-step graph with unchanged ids' do
      steps = workflow_body('refactor')['steps']
      expect(steps.size).to eq(8)
      expect(steps.map { |step| step['id'] }).to eq(expected_step_ids)
    end

    it 'declares spec_delta as an optional tasks-scoped artifact with no creating step' do
      body = workflow_body('refactor')
      spec_delta = body.dig('artifacts', 'spec_delta')
      expect(spec_delta).to include(
        'type' => 'spec_delta',
        'optional' => true,
        'storage' => { 'role' => 'tasks', 'path' => '{{task.id}}/spec_delta.md' }
      )
      creators = body['steps'].select { |step| Array(step['creates']).include?('spec_delta') }
      expect(creators).to be_empty
    end
  end

  describe 'lean hotfix (v1.6.0)' do
    it 'validates with valid:true' do
      body = JSON.parse(run_cli(['workflow', 'validate', 'hotfix', '--json'], cwd: repo_root))
      expect(body).to include('ok' => true, 'valid' => true, 'id' => 'hotfix')
    end

    it 'is a lean 4-step flow with no design/plan/merge_docs/archive' do
      steps = workflow_body('hotfix')['steps'].map { |step| step['id'] }
      expect(steps).to eq(%w[brief implement review_code commit_push])
    end

    it 'drops the design/plan/spec_delta artifacts' do
      artifacts = workflow_body('hotfix')['artifacts'].keys
      expect(artifacts).to contain_exactly('brief', 'review', 'verification')
    end

    it 'implement requires the brief (no plan step)' do
      implement = workflow_body('hotfix')['steps'].find { |step| step['id'] == 'implement' }
      expect(implement['requires']).to eq(['brief'])
    end
  end
end
