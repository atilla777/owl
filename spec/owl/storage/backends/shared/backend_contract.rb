# frozen_string_literal: true

# Shared contract for any Owl::Storage::Backend implementation.
#
# Host group contract:
#   let(:project_root) — Pathname to a writable project root with `.owl/`
#                        already created when relevant (the contract that
#                        depends on it creates it inline).
#   let(:backend)      — backend instance bound to project_root.
#
# Filesystem is the only current implementation; future backends (SQLite,
# HTTP) must include this shared_examples block and pass every example.
# The concurrent-write example is intentionally `pending` until a backend
# that needs cross-process write isolation (SQLite container) implements it.
RSpec.shared_examples 'Owl storage backend contract' do
  describe '#write then #read' do
    it 'round-trips bytes identically' do
      target = "#{project_root}/contract/round-trip.txt"
      payload = "first line\nsecond line\nthird line\n"

      write_result = backend.write(path: target, contents: payload)
      expect(write_result).to be_ok

      read_result = backend.read(path: target)
      expect(read_result).to be_ok
      expect(read_result.value).to eq(payload)
    end
  end

  describe '#read on a missing key' do
    it 'returns Result.err(:file_not_found) with path details' do
      result = backend.read(path: "#{project_root}/contract/missing.txt")

      expect(result).to be_err
      expect(result.code).to eq(:file_not_found)
      expect(result.details[:path]).to eq("#{project_root}/contract/missing.txt")
    end
  end

  describe '#exists?' do
    it 'is false before write and true after write' do
      target = "#{project_root}/contract/exists-probe.txt"

      expect(backend.exists?(path: target)).to be(false)
      backend.write(path: target, contents: 'x')
      expect(backend.exists?(path: target)).to be(true)
    end
  end

  describe '#mkdir_p' do
    it 'is idempotent across repeated calls' do
      target = "#{project_root}/contract/nested/dir"

      first = backend.mkdir_p(path: target)
      second = backend.mkdir_p(path: target)

      expect(first).to be_ok
      expect(second).to be_ok
    end
  end

  describe '#resolve with an unknown role' do
    it 'returns Result.err(:unknown_role) with an :available list' do
      profile = {
        'roles' => {
          'control' => { 'path' => '{{project.root}}/.owl' },
          'tasks' => { 'path' => '{{project.root}}/tasks' }
        }
      }

      result = backend.resolve(role: :ghost, profile: profile)

      expect(result).to be_err
      expect(result.code).to eq(:unknown_role)
      expect(result.details[:available]).to include('control', 'tasks')
    end
  end

  describe '#detect_root' do
    it 'returns Result.err(:project_root_not_found) without an .owl/ marker' do
      nested = Pathname.new("#{project_root}/contract/lone")
      nested.mkpath

      result = backend.detect_root(start: nested.to_s)

      expect(result).to be_err
      expect(result.code).to eq(:project_root_not_found)
    end

    it 'finds the project root when an .owl/ marker exists upwards' do
      Pathname.new("#{project_root}/.owl").mkpath
      nested = Pathname.new("#{project_root}/contract/inner")
      nested.mkpath

      result = backend.detect_root(start: nested.to_s)

      expect(result).to be_ok
      expect(result.value.to_s).to eq(project_root.expand_path.to_s)
    end
  end

  describe 'concurrent writes' do
    it 'serializes overlapping writes to the same key' do
      pending('SQLite backend (or any backend with cross-process state): must implement write isolation')
      raise 'pending example reached its assertion path — implement concurrent-write semantics'
    end
  end
end
