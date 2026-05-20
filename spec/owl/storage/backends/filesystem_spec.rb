# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

require 'owl/storage/backends/filesystem'
require_relative 'shared/backend_contract'

RSpec.describe Owl::Storage::Backends::Filesystem do
  describe 'satisfies the Storage backend contract' do
    let(:project_root) { Pathname.new(Dir.mktmpdir('owl-contract-')) }
    let(:backend) { described_class.new(root: project_root) }

    after { FileUtils.remove_entry_secure(project_root.to_s) if project_root.exist? }

    it_behaves_like 'Owl storage backend contract'
  end

  describe 'filesystem-specific behavior' do
    let(:profile) do
      {
        'backend' => 'filesystem',
        'roles' => {
          'control' => { 'path' => '{{project.root}}/.owl' },
          'tasks' => { 'path' => '{{project.root}}/tasks' },
          'mirror' => { 'path' => '{{env.OWL_TEST_MIRROR}}' }
        }
      }
    end

    describe '#write' do
      it 'returns a Pathname for the written file and creates parent directories' do
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
  end
end
