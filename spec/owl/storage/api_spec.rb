# frozen_string_literal: true

require 'owl/storage/api'

RSpec.describe Owl::Storage::Api do
  describe '.detect_root' do
    it 'finds the project root when .owl/ is present in an ancestor directory' do
      with_tmp_project do |root|
        Pathname.new("#{root}/.owl").mkpath
        nested = Pathname.new("#{root}/src/inner/path")
        nested.mkpath

        result = described_class.detect_root(start: nested.to_s)

        expect(result).to be_ok
        expect(result.value).to eq(root.expand_path)
      end
    end

    it 'returns an error when no .owl/ directory exists upwards' do
      with_tmp_project do |root|
        nested = Pathname.new("#{root}/lone/dir")
        nested.mkpath

        result = described_class.detect_root(start: nested.to_s)

        expect(result).to be_err
        expect(result.code).to eq(:project_root_not_found)
        expect(result.details[:start]).to eq(nested.to_s)
      end
    end
  end

  describe '.resolve' do
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

    it 'expands {{project.root}} into an absolute path' do
      with_tmp_project do |root|
        result = described_class.resolve(role: :tasks, profile: profile, root: root)

        expect(result).to be_ok
        expect(result.value.to_s).to eq("#{root.expand_path}/tasks")
      end
    end

    it 'expands {{env.X}} variables' do
      with_tmp_project do |root|
        ENV['OWL_TEST_MIRROR'] = '/srv/mirror'
        begin
          outcome = described_class.resolve(role: 'mirror', profile: profile, root: root)
          expect(outcome).to be_ok
          expect(outcome.value.to_s).to eq('/srv/mirror')
        ensure
          ENV.delete('OWL_TEST_MIRROR')
        end
      end
    end

    it 'returns an error for an unknown role' do
      with_tmp_project do |root|
        result = described_class.resolve(role: :ghost, profile: profile, root: root)

        expect(result).to be_err
        expect(result.code).to eq(:unknown_role)
        expect(result.details[:available]).to include('control', 'tasks', 'docs', 'mirror')
      end
    end

    it 'returns an error when a template references an unknown variable' do
      profile_with_bad_template = {
        'roles' => {
          'control' => { 'path' => '{{project.root}}/{{unknown.thing}}' }
        }
      }

      with_tmp_project do |root|
        result = described_class.resolve(role: 'control', profile: profile_with_bad_template, root: root)

        expect(result).to be_err
        expect(result.code).to eq(:unknown_path_variable)
        expect(result.details[:key]).to eq('unknown.thing')
      end
    end

    it 'returns an error when the active profile has no roles map at all' do
      result = described_class.resolve(role: 'tasks', profile: { 'backend' => 'filesystem' }, root: '/tmp')

      expect(result).to be_err
      expect(result.code).to eq(:unknown_role)
    end

    it 'merges nested vars and lets callers override base scopes' do
      nested_profile = {
        'roles' => {
          'custom' => { 'path' => '{{project.root}}/{{project.id}}/{{task.id}}/{{cwd}}' }
        }
      }

      with_tmp_project do |root|
        result = described_class.resolve(
          role: 'custom',
          profile: nested_profile,
          root: root,
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
  end

  describe '.write / .read / .exists? / .mkdir_p' do
    it 'writes a file, confirms existence, and reads it back' do
      with_tmp_project do |root|
        path = "#{root}/deep/nested/file.txt"
        expect(described_class.exists?(path: path)).to be(false)

        write_result = described_class.write(path: path, contents: "hello\n")
        expect(write_result).to be_ok
        expect(described_class.exists?(path: path)).to be(true)

        read_result = described_class.read(path: path)
        expect(read_result).to be_ok
        expect(read_result.value).to eq("hello\n")
      end
    end

    it 'returns a structured error when reading a missing file' do
      with_tmp_project do |root|
        result = described_class.read(path: "#{root}/missing.txt")

        expect(result).to be_err
        expect(result.code).to eq(:file_not_found)
      end
    end

    it 'creates nested directories with mkdir_p' do
      with_tmp_project do |root|
        path = Pathname.new("#{root}/a/b/c")
        result = described_class.mkdir_p(path: path)
        expect(result).to be_ok
        expect(path.directory?).to be(true)
      end
    end
  end
end
