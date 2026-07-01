# frozen_string_literal: true

require 'stringio'
require 'yaml'

require 'owl/cli/api'
require 'owl/tasks/api'

RSpec.describe 'Owl::Tasks::Api.stale_steps' do
  def cli(argv, root)
    Owl::Cli::Api.run(argv: argv, stdout: StringIO.new, stderr: StringIO.new, env: {}, cwd: root.to_s)
  end

  def setup_running_task(root)
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
    cli(['step', 'start', 'TASK-0001', 'build', '--root', root.to_s, '--json'], root)
  end

  def lease_path(root)
    Dir.glob("#{root}/.owl/local/claims/*.yaml").first
  end

  def backdate_lease(root)
    path = lease_path(root)
    lease = YAML.safe_load_file(path)
    lease['expires_at'] = (Time.now.utc - 3600).iso8601
    File.write(path, YAML.safe_dump(lease))
  end

  it 'flags a running step whose task holds an expired lease' do
    with_tmp_project do |root|
      setup_running_task(root)
      cli(['task', 'claim', 'TASK-0001', '--root', root.to_s, '--json'], root)
      backdate_lease(root)

      stale = Owl::Tasks::Api.stale_steps(root: root).value[:stale_steps]
      expect(stale).to contain_exactly(
        hash_including(task_id: 'TASK-0001', step_id: 'build', lease: 'expired',
                       suggestion: 'owl task adopt TASK-0001')
      )
    end
  end

  it 'does not flag a running step whose lease is still live' do
    with_tmp_project do |root|
      setup_running_task(root)
      cli(['task', 'claim', 'TASK-0001', '--root', root.to_s, '--json'], root)

      expect(Owl::Tasks::Api.stale_steps(root: root).value[:stale_steps]).to be_empty
    end
  end

  it 'does not flag a running step that has no lease at all (normal single-session)' do
    with_tmp_project do |root|
      setup_running_task(root)

      expect(Owl::Tasks::Api.stale_steps(root: root).value[:stale_steps]).to be_empty
    end
  end

  it 'is empty when there are no claims' do
    with_tmp_project do |root|
      setup_running_task(root)
      # complete the step so nothing is running, no lease taken
      cli(['step', 'complete', 'TASK-0001', 'build', '--root', root.to_s, '--json'], root)

      expect(Owl::Tasks::Api.stale_steps(root: root).value[:stale_steps]).to be_empty
    end
  end
end
