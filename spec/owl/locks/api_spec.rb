# frozen_string_literal: true

require 'pathname'
require 'stringio'
require 'yaml'

require 'owl/locks/api'
require 'owl/cli/internal/commands/init'

RSpec.describe Owl::Locks::Api do
  def init_project(root)
    Owl::Cli::Internal::Commands::Init.run(
      argv: ['--root', root.to_s], stdout: StringIO.new, stderr: StringIO.new, cwd: root.to_s, env: {}
    )
  end

  def lock_file(root, name = 'git')
    Pathname.new("#{root}/.owl/local/#{name}.lock")
  end

  describe '.acquire / .release' do
    it 'acquires a lock, writes the file, and returns a token' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.acquire(root: root, name: 'git')
        expect(result).to be_ok
        expect(result.value[:name]).to eq('git')
        expect(result.value[:token]).to be_a(String)
        expect(result.value[:ttl_seconds]).to eq(120)
        expect(lock_file(root)).to exist
      end
    end

    it 'honours an explicit ttl' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.acquire(root: root, name: 'git', ttl: 30)
        expect(result.value[:ttl_seconds]).to eq(30)
      end
    end

    it 'returns lock_held (recoverable) when the lock is live' do
      with_tmp_project do |root|
        init_project(root)
        described_class.acquire(root: root, name: 'git')
        result = described_class.acquire(root: root, name: 'git')
        expect(result).to be_err
        expect(result.code).to eq(:lock_held)
        expect(result.error_class).to eq(:recoverable)
      end
    end

    it 'steals a live lock with steal: true' do
      with_tmp_project do |root|
        init_project(root)
        first = described_class.acquire(root: root, name: 'git')
        result = described_class.acquire(root: root, name: 'git', steal: true)
        expect(result).to be_ok
        expect(result.value[:token]).not_to eq(first.value[:token])
      end
    end

    it 'reclaims an expired lock on the next acquire' do
      with_tmp_project do |root|
        init_project(root)
        path = lock_file(root)
        path.dirname.mkpath
        path.write(YAML.dump('name' => 'git', 'token' => 'dead', 'expires_at' => '2000-01-01T00:00:00Z'))
        result = described_class.acquire(root: root, name: 'git')
        expect(result).to be_ok
        expect(result.value[:token]).not_to eq('dead')
      end
    end

    it 'releases a held lock with the right token' do
      with_tmp_project do |root|
        init_project(root)
        acquire = described_class.acquire(root: root, name: 'git')
        result = described_class.release(root: root, name: 'git', token: acquire.value[:token])
        expect(result).to be_ok
        expect(result.value[:released]).to be(true)
        expect(lock_file(root)).not_to exist
      end
    end

    it 'returns lock_not_owned when releasing with the wrong token' do
      with_tmp_project do |root|
        init_project(root)
        described_class.acquire(root: root, name: 'git')
        result = described_class.release(root: root, name: 'git', token: 'nope')
        expect(result).to be_err
        expect(result.code).to eq(:lock_not_owned)
      end
    end

    it 'returns lock_not_found when releasing an unheld lock' do
      with_tmp_project do |root|
        init_project(root)
        result = described_class.release(root: root, name: 'git', token: 'x')
        expect(result).to be_err
        expect(result.code).to eq(:lock_not_found)
      end
    end
  end

  describe 'backend resolution via Owl::Internal::BackendResolver' do
    it 'returns Result.err(:unknown_backend) from .acquire when backend is unrecognised' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/.owl/config.yaml",
              File.read("#{root}/.owl/config.yaml") + "settings:\n  storage:\n    backend: imaginary\n")
        result = described_class.acquire(root: root, name: 'git')
        expect(result).to be_err
        expect(result.code).to eq(:unknown_backend)
        expect(result.details).to include(scope: :locks, backend_name: 'imaginary')
      end
    end

    it 'returns Result.err(:unknown_backend) from .release when backend is unrecognised' do
      with_tmp_project do |root|
        init_project(root)
        write("#{root}/.owl/config.yaml",
              File.read("#{root}/.owl/config.yaml") + "settings:\n  storage:\n    backend: imaginary\n")
        result = described_class.release(root: root, name: 'git', token: 'x')
        expect(result).to be_err
        expect(result.code).to eq(:unknown_backend)
      end
    end
  end
end
