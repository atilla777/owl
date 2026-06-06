# frozen_string_literal: true

require 'json'
require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/cli/api'

# TASK-0009: the hotfix and refactor workflows declare the optional `spec_delta`
# artifact (parity with feature, TASK-0007) without adding a creating step, and
# still validate end-to-end with their 8-step graph unchanged.
RSpec.describe 'hotfix/refactor declare the optional spec_delta artifact' do
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

  %w[hotfix refactor].each do |name|
    describe name do
      it 'validates with valid:true' do
        body = JSON.parse(run_cli(['workflow', 'validate', name, '--json'], cwd: repo_root))
        expect(body).to include('ok' => true, 'valid' => true, 'id' => name)
      end

      it 'keeps the 8-step graph with unchanged ids' do
        steps = workflow_body(name)['steps']
        expect(steps.size).to eq(8)
        expect(steps.map { |step| step['id'] }).to eq(expected_step_ids)
      end

      it 'declares spec_delta as an optional tasks-scoped artifact with no creating step' do
        body = workflow_body(name)
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
  end
end
