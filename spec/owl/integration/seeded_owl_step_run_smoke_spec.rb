# frozen_string_literal: true

require 'json'
require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/steps/api'

RSpec.describe 'seeded feature workflow with owl-step-run (end-to-end)' do
  def cli(argv, root)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: root.to_s)
    [stdout.string, stderr.string]
  end

  def feature_step_ids(workflow_yaml)
    YAML.safe_load(workflow_yaml.read).fetch('steps').map { |step| step['id'] }
  end

  def feature_steps(workflow_yaml)
    YAML.safe_load(workflow_yaml.read).fetch('steps')
  end

  def context_files_for(step)
    if step['variants'].is_a?(Hash) && !step['variants'].empty?
      step['variants'].map { |_, body| body['context_file'] }
    else
      ["#{step['id']}.context.md"]
    end
  end

  it 'init seeds workflow + context files and owl step show resolves owl-step-run for every step' do
    with_tmp_project do |root|
      cli(['init', '--root', root.to_s], root)

      workflow_yaml = root + '.owl/workflows/feature/workflow.yaml'
      expect(workflow_yaml.exist?).to be(true)
      steps = feature_steps(workflow_yaml)

      steps.each do |step|
        context_files_for(step).each do |relative|
          context_md = root + ".owl/workflows/feature/#{relative}"
          expect(context_md.exist?).to be(true), "missing #{context_md}"
          body = context_md.read
          expect(body).to include('# Purpose'),
                          -> { "#{context_md} missing '# Purpose' heading" }
        end
      end

      task_create_args = ['task', 'create', '--workflow', 'feature', '--title', 'smoke',
                          '--root', root.to_s, '--json']
      stdout, = cli(task_create_args, root)
      task_id = JSON.parse(stdout).dig('task', 'id')
      expect(task_id).to be_a(String)

      steps.each do |step|
        step_id = step['id']
        result = Owl::Steps::Api.show(root: root, task_id: task_id, step_id: step_id)
        message = result.respond_to?(:message) ? result.message : nil
        expect(result).to be_ok, "owl step show failed for #{step_id}: #{message}"

        bundle = result.value
        expect(bundle[:step]['id']).to eq(step_id)
        skill = bundle[:step]['skill']
        expect(skill).to eq('owl-step-run'), "#{step_id} bound to #{skill.inspect}, want owl-step-run"
        expect(bundle[:context]).to be_a(String).and(include('Purpose'))
      end
    end
  end
end
