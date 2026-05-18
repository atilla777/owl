# frozen_string_literal: true

require 'fileutils'
require 'pathname'

require 'owl/tasks/internal/archive/destination_planner'

RSpec.describe Owl::Tasks::Internal::Archive::DestinationPlanner do
  let(:now) { Time.utc(2026, 5, 17, 12, 0, 0) }

  describe '.call' do
    it 'returns the base name when no collision exists' do
      with_tmp_project do |root|
        archive_root = root + 'archive'
        FileUtils.mkdir_p(archive_root.to_s)

        result = described_class.call(
          archive_root: archive_root,
          task_id: 'TASK-0001',
          slug: 'feature-foo',
          now: now
        )
        expect(result).to be_ok
        expect(result.value[:base_name]).to eq('2026-05-17-TASK-0001-feature-foo')
        expect(result.value[:collision_suffix]).to be_nil
        expect(result.value[:destination_path]).to eq(archive_root + '2026-05-17-TASK-0001-feature-foo')
      end
    end

    it 'appends -2 when the base directory already exists' do
      with_tmp_project do |root|
        archive_root = root + 'archive'
        FileUtils.mkdir_p((archive_root + '2026-05-17-TASK-0001-foo').to_s)

        result = described_class.call(
          archive_root: archive_root,
          task_id: 'TASK-0001',
          slug: 'foo',
          now: now
        )
        expect(result).to be_ok
        expect(result.value[:base_name]).to eq('2026-05-17-TASK-0001-foo-2')
        expect(result.value[:collision_suffix]).to eq(2)
      end
    end

    it 'increments past existing suffixes' do
      with_tmp_project do |root|
        archive_root = root + 'archive'
        FileUtils.mkdir_p((archive_root + '2026-05-17-TASK-0001-foo').to_s)
        FileUtils.mkdir_p((archive_root + '2026-05-17-TASK-0001-foo-2').to_s)

        result = described_class.call(
          archive_root: archive_root,
          task_id: 'TASK-0001',
          slug: 'foo',
          now: now
        )
        expect(result).to be_ok
        expect(result.value[:base_name]).to eq('2026-05-17-TASK-0001-foo-3')
        expect(result.value[:collision_suffix]).to eq(3)
      end
    end

    it 'returns slug_collision_limit when the collision cap is exceeded' do
      with_tmp_project do |root|
        archive_root = root + 'archive'
        FileUtils.mkdir_p(archive_root.to_s)
        # Pre-create base + suffixes -2 through -100 (100 directories).
        FileUtils.mkdir_p((archive_root + '2026-05-17-TASK-0001-foo').to_s)
        (2..100).each do |suffix|
          FileUtils.mkdir_p((archive_root + "2026-05-17-TASK-0001-foo-#{suffix}").to_s)
        end

        result = described_class.call(
          archive_root: archive_root,
          task_id: 'TASK-0001',
          slug: 'foo',
          now: now
        )
        expect(result).to be_err
        expect(result.code).to eq(:slug_collision_limit)
      end
    end
  end
end
