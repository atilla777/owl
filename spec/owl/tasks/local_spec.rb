# frozen_string_literal: true

require 'owl/tasks/local'

RSpec.describe Owl::Tasks::Local do
  describe Owl::Tasks::Local::TaskFile do
    it 'stores task_path as a value attribute and compares by value' do
      a = described_class.new(task_path: '/tmp/p/tasks/TASK-0001/task.yaml')
      b = described_class.new(task_path: '/tmp/p/tasks/TASK-0001/task.yaml')
      expect(a).to eq(b)
      expect(a.task_path).to eq('/tmp/p/tasks/TASK-0001/task.yaml')
    end
  end

  describe Owl::Tasks::Local::Index do
    it 'stores index_path as a value attribute' do
      idx = described_class.new(index_path: '/tmp/p/tasks/index.yaml')
      expect(idx.index_path).to eq('/tmp/p/tasks/index.yaml')
    end
  end

  describe Owl::Tasks::Local::Pointer do
    it 'stores pointer_path as a value attribute' do
      ptr = described_class.new(pointer_path: '/tmp/p/.owl/local/current.yaml')
      expect(ptr.pointer_path).to eq('/tmp/p/.owl/local/current.yaml')
    end
  end
end
