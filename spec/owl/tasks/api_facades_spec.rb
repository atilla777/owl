# frozen_string_literal: true

require 'stringio'

require 'owl/tasks/api'
require 'owl/cli/internal/commands/init'

# Coverage for the cli-adapter facades that front Tasks::Internal::Paths /
# TaskReader (TASK-0040 WS3). Thin pass-throughs; the underlying resolution and
# read semantics are covered in the Internal specs.
RSpec.describe Owl::Tasks::Api do
  def init_project(root)
    Owl::Cli::Internal::Commands::Init.run(
      argv: ['--root', root.to_s], stdout: StringIO.new, stderr: StringIO.new,
      cwd: root.to_s, env: {}
    )
  end

  describe '.resolve_paths' do
    it 'resolves the tasks / index / local_state roots on an initialized project' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.resolve_paths(root: root)
        expect(result).to be_ok
        expect(result.value).to include(:tasks, :index, :local_state)
      end
    end
  end

  describe '.read_task' do
    it 'returns Err task_not_found for an unknown task' do
      with_tmp_project do |root|
        init_project(root)
        paths = described_class.resolve_paths(root: root)
        result = described_class.read_task(tasks_root: paths.value[:tasks], task_id: 'TASK-9999')
        expect(result).to be_err
        expect(result.code).to eq(:task_not_found)
      end
    end
  end
end
