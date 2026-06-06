# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/cli/api'

# TASK-0009: the hotfix and refactor merge_docs steps now run `owl spec merge`
# alongside `owl publish`. A spec-less hotfix/refactor task must see ZERO
# behavioural change — `owl spec merge` is a clean no-op that writes nothing
# under specs/.
RSpec.describe 'hotfix/refactor merge_docs spec merge is a no-op without a spec_delta' do
  def repo_root
    Pathname.new(File.expand_path('../../..', __dir__))
  end

  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
    [exit_code, stdout.string, stderr.string]
  end

  def init_project(root)
    run(['init', '--root', root.to_s], cwd: root)
  end

  # hotfix/refactor are project-local control-plane workflows (not part of the
  # gem seed that `owl init` scaffolds), so install them into the tmp project
  # from this repo's active `.owl/workflows/` and register them.
  def install_workflow(root, name)
    src = repo_root.join('.owl', 'workflows', name)
    FileUtils.cp_r(src.to_s, "#{root}/.owl/workflows/#{name}")

    registry_path = Pathname.new("#{root}/.owl/workflows.yaml")
    registry = YAML.safe_load(registry_path.read)
    registry['workflows'][name] = {
      'enabled' => true,
      'version' => '1.0',
      'title' => name.capitalize,
      'source' => "workflows/#{name}/workflow.yaml"
    }
    registry_path.write(YAML.dump(registry))
  end

  def create_task(root, workflow)
    _, stdout, = run(['task', 'create', '--workflow', workflow, '--title', 'spec-less', '--json'], cwd: root)
    JSON.parse(stdout).dig('task', 'id')
  end

  %w[hotfix refactor].each do |workflow|
    it "is a clean no-op for a spec-less #{workflow} task (writes nothing under specs/)" do
      with_tmp_project do |root|
        init_project(root)
        install_workflow(root, workflow)
        task_id = create_task(root, workflow)

        exit_code, stdout, = run(['spec', 'merge', task_id, '--root', root.to_s, '--json'], cwd: root)

        expect(exit_code).to eq(0)
        body = JSON.parse(stdout)
        expect(body).to include('ok' => true, 'applied' => false, 'reason' => 'no_spec_delta')
        expect(Pathname.new("#{root}/specs").exist?).to be(false)
      end
    end

    it "instructs the #{workflow} executor to run both owl publish and owl spec merge" do
      with_tmp_project do |root|
        init_project(root)
        install_workflow(root, workflow)
        context = Pathname.new("#{root}/.owl/workflows/#{workflow}/merge_docs.context.md").read
        expect(context).to include('owl publish TASK-ID')
        expect(context).to include('owl spec merge TASK-ID')
      end
    end
  end
end
