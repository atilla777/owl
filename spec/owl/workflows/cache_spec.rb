# frozen_string_literal: true

require 'tmpdir'
require 'pathname'
require 'yaml'

require 'owl/workflows/internal/cache'

RSpec.describe Owl::Workflows::Internal::Cache do
  around do |example|
    Dir.mktmpdir('owl-workflows-cache-spec') do |dir|
      @tmp_root = Pathname.new(dir)
      example.run
    end
  end

  let(:path) { @tmp_root.join('w.yaml') }

  describe '.fetch_yaml' do
    it 'invokes the block once for repeated reads of an unchanged file' do
      path.write("kind: feature\nsteps: []\n")
      calls = 0

      first = described_class.fetch_yaml(path) do
        calls += 1
        YAML.safe_load(path.read)
      end
      second = described_class.fetch_yaml(path) do
        calls += 1
        YAML.safe_load(path.read)
      end

      expect(calls).to eq(1)
      expect(first).to eq('kind' => 'feature', 'steps' => [])
      expect(second).to equal(first)
    end

    it 're-invokes the block when mtime changes' do
      path.write("a: 1\n")
      described_class.fetch_yaml(path) { YAML.safe_load(path.read) }

      bumped = Time.now + 60
      File.utime(bumped, bumped, path)
      path.write("a: 2\n")
      # The write above updates both mtime and size; nudge mtime explicitly to be sure.
      File.utime(bumped, bumped, path)

      calls = 0
      value = described_class.fetch_yaml(path) do
        calls += 1
        YAML.safe_load(path.read)
      end

      expect(calls).to eq(1)
      expect(value).to eq('a' => 2)
    end

    it 're-invokes the block when size changes but mtime is the same' do
      path.write("a: 1\n")
      first_stat = File.stat(path)
      described_class.fetch_yaml(path) { YAML.safe_load(path.read) }

      path.write("a: 1\nb: 2\n")
      # Force the new file to have the original mtime so only size differs.
      File.utime(first_stat.mtime, first_stat.mtime, path)

      calls = 0
      value = described_class.fetch_yaml(path) do
        calls += 1
        YAML.safe_load(path.read)
      end

      expect(calls).to eq(1)
      expect(value).to eq('a' => 1, 'b' => 2)
    end

    it 'raises Errno::ENOENT when the file does not exist' do
      missing = @tmp_root.join('missing.yaml')

      expect do
        described_class.fetch_yaml(missing) { :unused }
      end.to raise_error(Errno::ENOENT)
    end

    it 'namespaces keys so other domains do not collide' do
      path.write("k: 1\n")
      described_class.fetch_yaml(path) { YAML.safe_load(path.read) }

      absolute = File.expand_path(path.to_s)
      stat = File.stat(absolute)
      token = [stat.mtime.to_r, stat.size]
      foreign_calls = 0
      Owl::Internal::Cache.fetch("artifact:#{absolute}", version_token: token) do
        foreign_calls += 1
        :foreign
      end

      expect(foreign_calls).to eq(1)
    end
  end
end
