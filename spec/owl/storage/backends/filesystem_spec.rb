# frozen_string_literal: true

require 'owl/storage/backends/filesystem'

RSpec.describe Owl::Storage::Backends::Filesystem do
  let(:profile) do
    {
      'backend' => 'filesystem',
      'roles' => {
        'control' => { 'path' => '{{project.root}}/.owl' },
        'tasks' => { 'path' => '{{project.root}}/tasks' },
        'docs' => { 'path' => '{{project.root}}/docs' },
        'mirror' => { 'path' => '{{env.OWL_TEST_MIRROR}}' }
      }
    }
  end

  describe '#read' do
    it 'returns Result.ok with file contents' do
      with_tmp_project do |root|
        write("#{root}/note.txt", "hello\n")
        backend = described_class.new(root: root)

        result = backend.read(path: "#{root}/note.txt")

        expect(result).to be_ok
        expect(result.value).to eq("hello\n")
      end
    end

    it 'returns Result.err(:file_not_found) for a missing file' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)

        result = backend.read(path: "#{root}/missing.txt")

        expect(result).to be_err
        expect(result.code).to eq(:file_not_found)
        expect(result.details[:path]).to eq("#{root}/missing.txt")
      end
    end
  end

  describe '#write' do
    it 'writes the file and creates parent directories' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)
        target = "#{root}/deep/nested/file.txt"

        result = backend.write(path: target, contents: "payload\n")

        expect(result).to be_ok
        expect(result.value).to be_a(Pathname)
        expect(Pathname.new(target).read).to eq("payload\n")
      end
    end
  end

  describe '#mkdir_p' do
    it 'creates nested directories idempotently' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)
        target = Pathname.new("#{root}/a/b/c")

        first = backend.mkdir_p(path: target)
        second = backend.mkdir_p(path: target)

        expect(first).to be_ok
        expect(second).to be_ok
        expect(target.directory?).to be(true)
      end
    end
  end

  describe '#exists?' do
    it 'returns true for an existing path and false otherwise' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)
        write("#{root}/here.txt", 'x')

        expect(backend.exists?(path: "#{root}/here.txt")).to be(true)
        expect(backend.exists?(path: "#{root}/nope.txt")).to be(false)
      end
    end
  end

  describe '#resolve' do
    it 'expands {{project.root}} using the backend-bound root' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)

        result = backend.resolve(role: :tasks, profile: profile)

        expect(result).to be_ok
        expect(result.value.to_s).to eq("#{root.expand_path}/tasks")
      end
    end

    it 'expands {{env.X}} variables' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)
        ENV['OWL_TEST_MIRROR'] = '/srv/mirror'
        begin
          result = backend.resolve(role: 'mirror', profile: profile)
          expect(result).to be_ok
          expect(result.value.to_s).to eq('/srv/mirror')
        ensure
          ENV.delete('OWL_TEST_MIRROR')
        end
      end
    end

    it 'returns :unknown_role for a role not declared in the profile' do
      with_tmp_project do |root|
        backend = described_class.new(root: root)

        result = backend.resolve(role: :ghost, profile: profile)

        expect(result).to be_err
        expect(result.code).to eq(:unknown_role)
        expect(result.details[:available]).to include('control', 'tasks', 'docs', 'mirror')
      end
    end

    it 'returns :unknown_path_variable when a template variable is missing' do
      bad_profile = {
        'roles' => {
          'control' => { 'path' => '{{project.root}}/{{unknown.thing}}' }
        }
      }

      with_tmp_project do |root|
        backend = described_class.new(root: root)

        result = backend.resolve(role: 'control', profile: bad_profile)

        expect(result).to be_err
        expect(result.code).to eq(:unknown_path_variable)
        expect(result.details[:key]).to eq('unknown.thing')
      end
    end

    it 'merges caller-supplied vars over base scopes' do
      nested_profile = {
        'roles' => {
          'custom' => { 'path' => '{{project.root}}/{{project.id}}/{{task.id}}/{{cwd}}' }
        }
      }

      with_tmp_project do |root|
        backend = described_class.new(root: root)

        result = backend.resolve(
          role: 'custom',
          profile: nested_profile,
          vars: {
            'project' => { 'id' => 'override' },
            'task' => { 'id' => 'TASK-0001' },
            'cwd' => '/explicit/cwd'
          }
        )

        expect(result).to be_ok
        expect(result.value.to_s).to eq("#{root.expand_path}/override/TASK-0001/explicit/cwd")
      end
    end

    it 'returns :unknown_role when the profile carries no roles map at all' do
      backend = described_class.new(root: '/tmp')
      result = backend.resolve(role: 'tasks', profile: { 'backend' => 'filesystem' })

      expect(result).to be_err
      expect(result.code).to eq(:unknown_role)
    end
  end

  describe '#detect_root' do
    it 'finds the project root walking up from a nested path' do
      with_tmp_project do |root|
        Pathname.new("#{root}/.owl").mkpath
        nested = Pathname.new("#{root}/src/inner/path")
        nested.mkpath
        backend = described_class.new(root: nil)

        result = backend.detect_root(start: nested.to_s)

        expect(result).to be_ok
        expect(result.value).to eq(root.expand_path)
      end
    end

    it 'returns :project_root_not_found when no .owl/ exists upwards' do
      with_tmp_project do |root|
        nested = Pathname.new("#{root}/lone/dir")
        nested.mkpath
        backend = described_class.new(root: nil)

        result = backend.detect_root(start: nested.to_s)

        expect(result).to be_err
        expect(result.code).to eq(:project_root_not_found)
        expect(result.details[:start]).to eq(nested.to_s)
      end
    end
  end
end
