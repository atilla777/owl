# frozen_string_literal: true

require 'tmpdir'
require 'pathname'
require 'yaml'

require 'owl/artifacts/internal/cache'

RSpec.describe Owl::Artifacts::Internal::Cache do
  around do |example|
    Dir.mktmpdir('owl-artifacts-cache-spec') do |dir|
      @tmp_root = Pathname.new(dir)
      example.run
    end
  end

  let(:path) { @tmp_root.join('a.yaml') }

  it 'invokes the block once for repeated reads of an unchanged file' do
    path.write("kind: spec\n")
    calls = 0

    described_class.fetch_yaml(path) { calls += 1; YAML.safe_load(path.read) }
    described_class.fetch_yaml(path) { calls += 1; YAML.safe_load(path.read) }

    expect(calls).to eq(1)
  end

  it 're-invokes the block when mtime changes' do
    path.write("k: 1\n")
    described_class.fetch_yaml(path) { YAML.safe_load(path.read) }

    bumped = Time.now + 60
    File.utime(bumped, bumped, path)
    path.write("k: 2\n")
    File.utime(bumped, bumped, path)

    calls = 0
    value = described_class.fetch_yaml(path) { calls += 1; YAML.safe_load(path.read) }

    expect(calls).to eq(1)
    expect(value).to eq('k' => 2)
  end

  it 'uses an artifact-namespaced key (does not collide with workflows)' do
    path.write("k: 1\n")
    require 'owl/workflows/internal/cache'

    Owl::Workflows::Internal::Cache.fetch_yaml(path) { YAML.safe_load(path.read) }

    calls = 0
    described_class.fetch_yaml(path) { calls += 1; YAML.safe_load(path.read) }

    expect(calls).to eq(1)
  end
end
