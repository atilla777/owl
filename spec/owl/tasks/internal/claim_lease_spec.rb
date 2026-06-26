# frozen_string_literal: true

require 'yaml'

require 'owl/tasks/api'
require 'owl/tasks/internal/availability_scanner'
require 'owl/tasks/internal/claim_paths'
require 'owl/tasks/internal/claim_service'
require 'owl/tasks/internal/exclusive_lease'
require 'owl/cli/internal/commands/init'

RSpec.describe 'Owl claim-lease internals (time-based branches)' do
  def init_project(root)
    Owl::Cli::Internal::Commands::Init.run(
      argv: ['--root', root.to_s], stdout: StringIO.new, stderr: StringIO.new, cwd: root.to_s, env: {}
    )
  end

  def seed(root)
    init_project(root)
    write("#{root}/.owl/workflows.yaml", <<~YAML)
      schema_version: 1
      workflows:
        feature:
          enabled: true
          source: "workflows/feature/workflow.yaml"
    YAML
    write("#{root}/.owl/workflows/feature/workflow.yaml", <<~YAML)
      id: feature
      kind: feature
      steps:
        - id: a
      artifacts: []
    YAML
    Owl::Tasks::Api.create(root: root, workflow: 'feature', title: 't')
  end

  let(:lease_path) { ->(root) { "#{root}/.owl/local/claims/TASK-0001.yaml" } }

  describe Owl::Tasks::Internal::ExclusiveLease do
    it 'reclaims an expired lease on a second acquire' do
      with_tmp_project do |root|
        seed(root)
        path = lease_path.call(root)
        t0 = Time.utc(2026, 1, 1, 12, 0, 0)
        described_class.acquire(path: path, payload: { 'task_id' => 'TASK-0001',
                                                       'expires_at' => (t0 + 1).utc.iso8601 }, now: t0)
        # Far in the future: the prior lease is expired and gets reclaimed.
        reclaimed = described_class.acquire(
          path: path, payload: { 'task_id' => 'TASK-0001', 'expires_at' => (t0 + 7200).utc.iso8601 },
          now: t0 + 3600
        )
        expect(reclaimed).to be_ok
      end
    end

    it 'rejects an unexpired lease' do
      with_tmp_project do |root|
        seed(root)
        path = lease_path.call(root)
        t0 = Time.utc(2026, 1, 1, 12, 0, 0)
        described_class.acquire(path: path, payload: { 'task_id' => 'TASK-0001',
                                                       'expires_at' => (t0 + 600).utc.iso8601 }, now: t0)
        held = described_class.acquire(path: path, payload: { 'task_id' => 'TASK-0001' }, now: t0 + 10)
        expect(held).to be_err
        expect(held.code).to eq(:lease_held)
      end
    end

    it 'treats a missing expires_at as expired' do
      expect(described_class.expired?({ 'expires_at' => nil }, Time.now.utc)).to be(true)
      expect(described_class.expired?({ 'expires_at' => 'not-a-time' }, Time.now.utc)).to be(true)
    end
  end

  describe Owl::Tasks::Internal::ClaimService do
    it 'reclaims an expired claim when the holder TTL has passed' do
      with_tmp_project do |root|
        seed(root)
        t0 = Time.utc(2026, 1, 1, 12, 0, 0)
        described_class.claim(root: root, task_id: 'TASK-0001', ttl: 60, now: t0)
        later = described_class.claim(root: root, task_id: 'TASK-0001', now: t0 + 3600)
        expect(later).to be_ok
        expect(later.value[:expires_at]).to eq((t0 + 3600 + Owl::Tasks::Internal::ClaimPaths::DEFAULT_TTL_SECONDS)
                                                 .utc.iso8601)
      end
    end

    it 'falls back to the default TTL for a non-positive ttl' do
      with_tmp_project do |root|
        seed(root)
        t0 = Time.utc(2026, 1, 1, 12, 0, 0)
        result = described_class.claim(root: root, task_id: 'TASK-0001', ttl: 0, now: t0)
        expect(result.value[:expires_at]).to eq((t0 + Owl::Tasks::Internal::ClaimPaths::DEFAULT_TTL_SECONDS)
                                                  .utc.iso8601)
      end
    end

    it 'marks an expired claim as expired in the claims listing' do
      with_tmp_project do |root|
        seed(root)
        t0 = Time.utc(2026, 1, 1, 12, 0, 0)
        described_class.claim(root: root, task_id: 'TASK-0001', ttl: 60, now: t0)
        listing = described_class.claims(root: root, now: t0 + 3600)
        expect(listing.value[:claims].first[:expired]).to be(true)
      end
    end
  end

  describe Owl::Tasks::Internal::AvailabilityScanner do
    it 'treats a task with an expired claim as available again' do
      with_tmp_project do |root|
        seed(root)
        t0 = Time.utc(2026, 1, 1, 12, 0, 0)
        Owl::Tasks::Internal::ClaimService.claim(root: root, task_id: 'TASK-0001', ttl: 60, now: t0)
        scan = described_class.scan(root: root, now: t0 + 3600)
        expect(scan.value[:available].map { |c| c['task_id'] }).to eq(['TASK-0001'])
      end
    end
  end
end
