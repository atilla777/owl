# frozen_string_literal: true

# Constitution meta-spec: enforces the Layer-C exception allowlist.
#
# Greps lib/owl/ for `File.*`, `FileUtils.*`, `Dir.*`, and `Pathname.new`
# and checks that every match falls in a file on the hardcoded allowlist
# below. Adding a new direct-FS callsite requires reviewing the list.
#
# The allowlist has three categories:
#
#   1. Backend implementations — `lib/owl/<domain>/{backends,internal}/...`
#      for the seven backend domains (tasks, storage, config, artifacts,
#      workflows, publish, validation). These are the abstraction's
#      implementation; the "no direct FS" rule is about callers, not them.
#
#   2. Layer-C exceptions (5 named, see clarification_log #127 D3):
#      bootstrap reads and writes that must run before any backend can
#      resolve, or that touch user-supplied paths outside any project.
#
#   3. Path-utility files — files using `File.expand_path`, `File.join`,
#      `Pathname.new(...).expand_path`, or `Dir.pwd` only as pure path-
#      math (not I/O). They are listed explicitly so that any new I/O
#      added to them gets caught by review.

module OwlConstitutionFixtures
  LIB_ROOT = File.expand_path('../../../lib/owl', __dir__)

  PATTERN = /\b(?:File|FileUtils|Dir)\.|\bPathname\.new\b/

  ALLOWLIST = %w[
    artifacts/backends/filesystem.rb
    artifacts/internal/artifact_type_loader.rb
    artifacts/internal/cache.rb
    artifacts/internal/registry_loader.rb
    artifacts/internal/source_loader.rb
    artifacts/internal/task_artifact_resolver.rb
    config/backends/filesystem.rb
    config/internal/loader.rb
    config/internal/serializer.rb
    publish/internal/path_resolver.rb
    publish/internal/publisher.rb
    steps/internal/active_step_lock.rb
    steps/internal/artifact_hasher.rb
    storage/backends/filesystem.rb
    storage/internal/filesystem_backend.rb
    subagents/internal/output_spec.rb
    storage/internal/root_detector.rb
    tasks/internal/archive/current_resetter.rb
    tasks/internal/archive/destination_planner.rb
    tasks/internal/archive/mover.rb
    tasks/internal/archive/orchestrator.rb
    tasks/internal/archive/path_rename.rb
    tasks/internal/atomic_yaml_writer.rb
    tasks/internal/child_creator.rb
    tasks/internal/current_pointer.rb
    tasks/internal/deleter.rb
    tasks/internal/id_generator.rb
    tasks/internal/index_reader.rb
    tasks/internal/index_rebuilder.rb
    tasks/internal/task_reader.rb
    validation/internal/schema_check.rb
    validation/internal/schema_resolver.rb
    workflows/backends/filesystem.rb
    workflows/internal/cache.rb
    workflows/internal/registry_loader.rb
    workflows/internal/source_loader.rb
    internal/backend_resolver.rb
    internal/gem_assets.rb
    cli/internal/user_file_reader.rb
    init/internal/scaffolder.rb
    internal/paths.rb
    cli/api.rb
    cli/internal/commands/config_get.rb
    cli/internal/commands/config_set.rb
    cli/internal/commands/config_show.rb
    cli/internal/commands/config_validate.rb
    cli/internal/commands/task_support.rb
    cli/internal/commands/workflow_list.rb
    cli/internal/commands/step_report.rb
    context/internal/overlay_paths.rb
    subagents/internal/tier_map.rb
    subagents/internal/report_paths.rb
    specs/internal/trace_checker.rb
  ].freeze
end

RSpec.describe 'Owl constitution: no direct filesystem access' do
  it 'flags any File/FileUtils/Dir/Pathname.new outside the allowlist' do
    offenders = []
    Dir.glob(File.join(OwlConstitutionFixtures::LIB_ROOT, '**', '*.rb')).each do |path|
      rel = path.delete_prefix("#{OwlConstitutionFixtures::LIB_ROOT}/")
      next if OwlConstitutionFixtures::ALLOWLIST.include?(rel)

      File.readlines(path).each_with_index do |line, idx|
        next if line.lstrip.start_with?('#')
        next unless OwlConstitutionFixtures::PATTERN.match?(line)

        offenders << "#{rel}:#{idx + 1} #{line.strip}"
      end
    end

    expect(offenders).to be_empty, lambda {
      "Direct File/FileUtils/Dir/Pathname.new outside Layer-C allowlist:\n  " +
        offenders.join("\n  ") +
        "\n\nIf this is legitimate, add the file to ALLOWLIST in this spec and " \
        'explain why (backend internal, Layer-C exception, or pure path-utility).'
    }
  end

  it 'allowlist itself does not list files that no longer exist' do
    missing = OwlConstitutionFixtures::ALLOWLIST.reject do |rel|
      File.file?(File.join(OwlConstitutionFixtures::LIB_ROOT, rel))
    end
    expect(missing).to be_empty, "Stale ALLOWLIST entries (files don't exist): #{missing.inspect}"
  end
end
