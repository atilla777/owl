# frozen_string_literal: true

require 'stringio'
require 'json'
require 'yaml'

require 'owl/cli/api'

RSpec.describe 'owl doctor (CLI)' do
  def cli(argv, root)
    out = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: out, stderr: StringIO.new, env: {}, cwd: root.to_s)
    out.string
  end

  def json(argv, root)
    JSON.parse(cli(argv, root))
  end

  def setup_project(root)
    cli(['init', '--root', root.to_s], root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        quick:
          enabled: true
          source: "workflows/quick/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/quick/workflow.yaml", <<~YAML)
      id: quick
      kind: task
      artifacts: {}
      steps:
        - id: build
    YAML
    cli(['task', 'create', '--workflow', 'quick', '--title', 't', '--root', root.to_s, '--json'], root)
  end

  it 'reports all three drift classes and touches nothing without --fix' do
    with_tmp_project do |root|
      setup_project(root)
      payload = json(['doctor', '--root', root.to_s, '--json'], root)

      expect(payload).to include(
        'ok' => true, 'drifted' => [], 'index_drift' => [],
        'stale_steps' => [], 'fixed' => [], 'index_rebuilt' => false
      )
    end
  end

  it '--fix rebuilds the index when index drift is present' do
    with_tmp_project do |root|
      setup_project(root)
      index = "#{root}/tasks/index.yaml"
      data = YAML.safe_load_file(index)
      data['tasks'] = []
      File.write(index, YAML.safe_dump(data))

      payload = json(['doctor', '--fix', '--root', root.to_s, '--json'], root)
      expect(payload['index_rebuilt']).to be(true)

      after = json(['doctor', '--root', root.to_s, '--json'], root)
      expect(after['index_drift']).to be_empty
    end
  end

  it '--fix promotes a workflow-complete but open task to done' do
    with_tmp_project do |root|
      setup_project(root)
      cli(['step', 'start', 'TASK-0001', 'build', '--root', root.to_s, '--json'], root)
      cli(['step', 'complete', 'TASK-0001', 'build', '--root', root.to_s, '--json'], root)
      cli(['task', 'set-status', 'TASK-0001', 'open', '--root', root.to_s, '--json'], root)

      payload = json(['doctor', '--fix', '--root', root.to_s, '--json'], root)
      expect(payload['fixed']).to contain_exactly(
        'task_id' => 'TASK-0001', 'from' => 'open', 'to' => 'done'
      )
    end
  end
end
