# frozen_string_literal: true

require 'stringio'

require 'owl/cli/api'
require 'owl/tasks/api'
require 'owl/tasks/internal/tree_builder'

RSpec.describe 'Owl::Tasks::Api.tree' do
  def run(argv, cwd:)
    stdout = StringIO.new
    stderr = StringIO.new
    Owl::Cli::Api.run(argv: argv, stdout: stdout, stderr: stderr, env: {}, cwd: cwd.to_s)
  end

  def init_with_workflows(root)
    run(['init', '--root', root.to_s], cwd: root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        composite_feature:
          enabled: true
          source: "workflows/composite_feature/workflow.yaml"
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/composite_feature/workflow.yaml",
          "id: composite_feature\nkind: composite_task\nsteps:\n  - id: only\nartifacts: []\n")
    write("#{root}/.owl/workflows/feature/workflow.yaml",
          "id: feature\nkind: task\nsteps:\n  - id: do\nartifacts: []\n")
  end

  # The MAX_DEPTH/cycle warnings test cases poke a synthetic `tasks/index.yaml`
  # directly to bypass the CLI-level guards that prevent cycle creation and
  # avoid the cost of creating 33 real task directories.
  def write_synthetic_index(root, entries)
    payload = { 'schema_version' => 1, 'tasks' => entries }
    write("#{root}/tasks/index.yaml", YAML.dump(payload))
  end

  it 'builds nested tree from index entries' do
    with_tmp_project do |root|
      init_with_workflows(root)
      run(['task', 'create', '--workflow', 'composite_feature', '--title', 'P', '--root', root.to_s], cwd: root)
      run(
        ['task', 'create', '--workflow', 'feature', '--title', 'C1', '--parent', 'TASK-0001', '--root',
         root.to_s], cwd: root
      )
      run(
        ['task', 'create', '--workflow', 'feature', '--title', 'C2', '--parent', 'TASK-0001', '--root',
         root.to_s], cwd: root
      )
      run(['task', 'create', '--workflow', 'feature', '--title', 'Orphan', '--root', root.to_s], cwd: root)

      result = Owl::Tasks::Api.tree(root: root)
      expect(result.ok?).to be(true)
      ids = result.value[:tasks].map { |n| n[:id] }
      expect(ids).to contain_exactly('TASK-0001', 'TASK-0004')
      parent_node = result.value[:tasks].find { |n| n[:id] == 'TASK-0001' }
      expect(parent_node[:children].map { |c| c[:id] }).to contain_exactly('TASK-0002', 'TASK-0003')
      expect(parent_node[:children].first[:children]).to eq([])
      expect(result.value[:warnings]).to eq([])
    end
  end

  it 'returns empty tree when no tasks exist' do
    with_tmp_project do |root|
      init_with_workflows(root)
      result = Owl::Tasks::Api.tree(root: root)
      expect(result.ok?).to be(true)
      expect(result.value[:tasks]).to eq([])
      expect(result.value[:warnings]).to eq([])
    end
  end

  context 'with MAX_DEPTH exceeded on a synthetic chain' do
    it 'emits one tree_truncated warning and marks the cut-off node as truncated' do
      with_tmp_project do |root|
        init_with_workflows(root)
        max_depth = Owl::Tasks::Internal::TreeBuilder::MAX_DEPTH
        chain_length = max_depth + 1
        entries = (1..chain_length).map do |i|
          {
            'id' => format('TASK-%04d', i),
            'title' => "Node #{i}",
            'workflow' => 'feature',
            'kind' => 'task',
            'parent_id' => (i == 1 ? nil : format('TASK-%04d', i - 1)),
            'status' => 'todo'
          }
        end
        write_synthetic_index(root, entries)

        result = Owl::Tasks::Api.tree(root: root)
        expect(result.ok?).to be(true)
        expect(result.value[:warnings].size).to eq(1)
        warning = result.value[:warnings].first
        expect(warning[:code]).to eq('tree_truncated')
        expect(warning[:max_depth]).to eq(max_depth)
        expect(warning[:at_path]).to eq((1..chain_length).map { |i| format('TASK-%04d', i) }.join('/'))
      end
    end

    it 'leaves warnings empty when depth is one below MAX_DEPTH' do
      with_tmp_project do |root|
        init_with_workflows(root)
        max_depth = Owl::Tasks::Internal::TreeBuilder::MAX_DEPTH
        chain_length = max_depth
        entries = (1..chain_length).map do |i|
          {
            'id' => format('TASK-%04d', i),
            'title' => "Node #{i}",
            'workflow' => 'feature',
            'kind' => 'task',
            'parent_id' => (i == 1 ? nil : format('TASK-%04d', i - 1)),
            'status' => 'todo'
          }
        end
        write_synthetic_index(root, entries)

        result = Owl::Tasks::Api.tree(root: root)
        expect(result.ok?).to be(true)
        expect(result.value[:warnings]).to eq([])
      end
    end
  end

  context 'with a parent_id cycle in the index' do
    it 'emits a tree_cycle warning with cycle_id and the path of the repetition' do
      with_tmp_project do |root|
        init_with_workflows(root)
        entries = [
          { 'id' => 'TASK-A', 'title' => 'A', 'workflow' => 'feature', 'kind' => 'task', 'parent_id' => nil,
            'status' => 'todo' },
          { 'id' => 'TASK-B', 'title' => 'B', 'workflow' => 'feature', 'kind' => 'task', 'parent_id' => 'TASK-A',
            'status' => 'todo' },
          { 'id' => 'TASK-A', 'title' => 'A repeat', 'workflow' => 'feature', 'kind' => 'task',
            'parent_id' => 'TASK-B', 'status' => 'todo' }
        ]
        write_synthetic_index(root, entries)

        result = Owl::Tasks::Api.tree(root: root)
        expect(result.ok?).to be(true)
        cycle_warnings = result.value[:warnings].select { |w| w[:code] == 'tree_cycle' }
        expect(cycle_warnings.size).to eq(1)
        expect(cycle_warnings.first[:cycle_id]).to eq('TASK-A')
        expect(cycle_warnings.first[:at_path]).to eq('TASK-A/TASK-B/TASK-A')
      end
    end
  end

  context 'with multiple independently truncated branches' do
    def deep_chain(prefix, length)
      (1..length).map do |i|
        {
          'id' => format("#{prefix}-%04d", i),
          'title' => "#{prefix}#{i}",
          'workflow' => 'feature',
          'kind' => 'task',
          'parent_id' => (i == 1 ? nil : format("#{prefix}-%04d", i - 1)),
          'status' => 'todo'
        }
      end
    end

    it 'emits one warning per truncated branch' do
      with_tmp_project do |root|
        init_with_workflows(root)
        max_depth = Owl::Tasks::Internal::TreeBuilder::MAX_DEPTH
        write_synthetic_index(root, deep_chain('A', max_depth + 1) + deep_chain('B', max_depth + 1))

        result = Owl::Tasks::Api.tree(root: root)
        expect(result.ok?).to be(true)
        truncated = result.value[:warnings].select { |w| w[:code] == 'tree_truncated' }
        expect(truncated.size).to eq(2)
        chains = truncated.map { |w| w[:at_path].split('/').first[0, 1] }.sort
        expect(chains).to eq(%w[A B])
      end
    end
  end

  context 'when a cycle occurs on a deep branch' do
    it 'reports tree_cycle (cycle check runs before depth check)' do
      with_tmp_project do |root|
        init_with_workflows(root)
        max_depth = Owl::Tasks::Internal::TreeBuilder::MAX_DEPTH

        # Linear chain of MAX_DEPTH entries, then a cycle node re-pointing back
        # to the chain head.
        prefix = (1..max_depth).map do |i|
          {
            'id' => format('C-%04d', i),
            'title' => "C#{i}",
            'workflow' => 'feature',
            'kind' => 'task',
            'parent_id' => (i == 1 ? nil : format('C-%04d', i - 1)),
            'status' => 'todo'
          }
        end
        cycle_back = {
          'id' => 'C-0001',
          'title' => 'C1 repeat',
          'workflow' => 'feature',
          'kind' => 'task',
          'parent_id' => format('C-%04d', max_depth),
          'status' => 'todo'
        }
        write_synthetic_index(root, prefix + [cycle_back])

        result = Owl::Tasks::Api.tree(root: root)
        expect(result.ok?).to be(true)
        cycles = result.value[:warnings].select { |w| w[:code] == 'tree_cycle' }
        expect(cycles.size).to be >= 1
        expect(cycles.first[:cycle_id]).to eq('C-0001')
      end
    end
  end
end
