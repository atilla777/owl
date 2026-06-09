# frozen_string_literal: true

require 'pathname'
require 'tmpdir'
require 'time'
require 'yaml'

require 'owl/locks/internal/file_lock'

RSpec.describe Owl::Locks::Internal::FileLock do
  let(:root_holder) { { root: nil } }
  let(:local_state) { root_holder[:root] }
  let(:now) { Time.utc(2026, 6, 9, 12, 0, 0) }

  around do |example|
    Dir.mktmpdir('owl-filelock-spec') do |dir|
      root_holder[:root] = Pathname.new(dir)
      example.run
    end
  end

  def acquire(token: nil, ttl: 120, steal: false, at: now)
    described_class.acquire(
      local_state_root: local_state, name: 'git', ttl: ttl, token: token, steal: steal, now: at
    )
  end

  it 'creates the lock file with a generated token when none is supplied' do
    result = acquire
    expect(result).to be_ok
    expect(result.value[:token]).to match(/\A[0-9a-f-]{36}\z/)
    expect(described_class.lock_path(local_state_root: local_state, name: 'git')).to exist
  end

  it 'uses the supplied token verbatim' do
    expect(acquire(token: 'session-7').value[:token]).to eq('session-7')
  end

  it 'rejects a second live acquire with lock_held (recoverable)' do
    acquire(token: 'a')
    result = acquire(token: 'b')
    expect(result.code).to eq(:lock_held)
    expect(result.error_class).to eq(:recoverable)
    expect(result.details[:existing]['token']).to eq('a')
  end

  it 'reclaims when the existing lock has expired' do
    acquire(token: 'old', ttl: 60, at: now)
    later = now + 3600
    result = acquire(token: 'new', at: later)
    expect(result).to be_ok
    expect(result.value[:token]).to eq('new')
  end

  it 'overwrites unconditionally with steal' do
    acquire(token: 'a')
    expect(acquire(token: 'b', steal: true).value[:token]).to eq('b')
  end

  describe '.release' do
    it 'removes the file when the token matches' do
      acquire(token: 'a')
      result = described_class.release(local_state_root: local_state, name: 'git', token: 'a')
      expect(result).to be_ok
      expect(described_class.lock_path(local_state_root: local_state, name: 'git')).not_to exist
    end

    it 'refuses a mismatched token' do
      acquire(token: 'a')
      result = described_class.release(local_state_root: local_state, name: 'git', token: 'z')
      expect(result.code).to eq(:lock_not_owned)
    end

    it 'reports lock_not_found for an absent lock' do
      result = described_class.release(local_state_root: local_state, name: 'git', token: 'a')
      expect(result.code).to eq(:lock_not_found)
    end

    it 'surfaces lock_invalid on a malformed lock file' do
      path = described_class.lock_path(local_state_root: local_state, name: 'git')
      path.dirname.mkpath
      path.write("not a mapping: : :\n  - x: y: z")
      result = described_class.release(local_state_root: local_state, name: 'git', token: 'a')
      expect(result.code).to eq(:lock_invalid)
    end
  end

  describe '.expired?' do
    it 'treats a missing expires_at as expired' do
      expect(described_class.expired?({}, now)).to be(true)
    end

    it 'treats an unparseable expires_at as expired' do
      expect(described_class.expired?({ 'expires_at' => 'not-a-time' }, now)).to be(true)
    end

    it 'treats a future expires_at as live' do
      expect(described_class.expired?({ 'expires_at' => (now + 60).utc.iso8601 }, now)).to be(false)
    end
  end
end
