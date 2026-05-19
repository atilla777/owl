# frozen_string_literal: true

require 'json'
require 'stringio'

require 'owl/artifacts/api'
require 'owl/cli/api'
require 'owl/validation/api'

# Per-artifact workflow that declares the artifact in its workflow.yaml.
# Otherwise resolve returns :unknown_workflow_artifact.
SEEDED_ARTIFACT_TEST_WORKFLOW = {
  'brief' => 'feature',
  'design' => 'feature',
  'plan' => 'feature',
  'review' => 'feature',
  'verification' => 'feature',
  'spec' => 'refactor',
  'tasks' => 'refactor',
  'decomposition' => 'composite_feature',
  'issue' => 'hotfix',
  'patch_plan' => 'hotfix',
  'research_findings' => 'research',
  'recommendation' => 'research'
}.freeze

RSpec.describe 'Seeded artifact template skeletons' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [stdout.string, stderr.string]
  end

  def init_project(root)
    run(['init', '--root', root.to_s], cwd: root)
  end

  Owl::Artifacts::Internal::SeededSources.keys.each do |artifact_key| # rubocop:disable Style/HashEachMethods
    it "validates the seeded default template skeleton for #{artifact_key}" do
      with_tmp_project do |root|
        init_project(root)

        workflow_key = SEEDED_ARTIFACT_TEST_WORKFLOW.fetch(artifact_key)
        stdout, _stderr = run(
          ['task', 'create', '--workflow', workflow_key, '--title', 't',
           '--root', root.to_s, '--json'],
          cwd: root
        )
        task_id = JSON.parse(stdout).dig('task', 'id')

        resolved = Owl::Artifacts::Api.resolve(root: root, task_id: task_id, artifact_key: artifact_key)
        expect(resolved).to be_ok, "resolve failed for #{artifact_key}: #{resolved.message if resolved.err?}"

        target = Pathname.new(resolved.value[:path])
        template = Pathname.new(resolved.value[:template_path])
        target.dirname.mkpath
        target.write(template.read)

        result = Owl::Validation::Api.artifact(root: root, task_id: task_id, artifact_key: artifact_key)
        expect(result).to be_ok, "validation failed for #{artifact_key}: #{result.message if result.err?}"
        expect(result.value[:valid]).to be(true),
                                        "skeleton for #{artifact_key} has violations: #{result.value[:violations]}"
      end
    end
  end
end
