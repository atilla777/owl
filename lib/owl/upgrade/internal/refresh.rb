# frozen_string_literal: true

require 'yaml'

require_relative '../../result'
require_relative '../../version'
require_relative '../../storage/api'
require_relative '../../config/api'
require_relative '../../skills/api'
require_relative '../../workflows/api'
require_relative '../../artifacts/api'
require_relative '../../workflows/internal/default_template'
require_relative '../../artifacts/internal/default_template'
require_relative '../../skills/internal/seeded_sources'
require_relative 'registry_merge'

module Owl
  module Upgrade
    module Internal
      # Provenance-aware refresh of an Owl project's copied seed content.
      #
      # Replaces Owl-shipped files (skills/commands always; per-type workflow and
      # artifact files unless their registry entry is `managed: false`) and
      # line-merges the two registries, while leaving project-owned content
      # (overlays, tasks, config edits, `managed: false` clones) untouched.
      module Refresh
        module_function

        def call(root:, dry_run: false, backup: true, targets: nil)
          root = root.to_s
          targets ||= resolve_targets(root)
          protected_wf = protected_ids(Owl::Workflows::Api.registry(root: root))
          protected_art = protected_ids(Owl::Artifacts::Api.registry(root: root))

          ctx = { root: root, dry_run: dry_run, backup: backup, stamp: timestamp,
                  replaced: [], preserved: [], backed_up: [] }

          refresh_skills(ctx, targets)
          refresh_seed(ctx, Owl::Workflows::Api.seeded_sources, '.owl/workflows/', protected_wf)
          refresh_seed(ctx, Owl::Artifacts::Api.seeded_sources, '.owl/artifacts/', protected_art)
          merged = refresh_registries(ctx)

          from = current_version(root)
          stamp_version(root) unless dry_run

          Result.ok(
            dry_run: dry_run,
            version: { from: from, to: Owl::VERSION },
            replaced: ctx[:replaced].sort,
            preserved: ctx[:preserved].sort,
            merged_registries: merged.sort,
            backed_up: ctx[:backed_up].sort,
            backup_dir: ctx[:backed_up].empty? ? nil : backup_dir(ctx)
          )
        end

        # --- categories ---------------------------------------------------------

        def refresh_skills(ctx, targets)
          Owl::Skills::Api.seeded_sources(targets: targets).each do |file|
            write_if_changed(ctx, file[:relative_path], file[:contents])
          end
        end

        def refresh_seed(ctx, sources, prefix, protected_set)
          sources.each do |file|
            rel = file[:relative_path]
            id = id_from(rel, prefix)
            if id && protected_set.include?(id)
              ctx[:preserved] << rel
            else
              write_if_changed(ctx, rel, file[:contents])
            end
          end
        end

        def refresh_registries(ctx)
          merged = []
          { '.owl/workflows.yaml' => [Owl::Workflows::Internal::DefaultTemplate.render, 'workflows'],
            '.owl/artifacts.yaml' => [Owl::Artifacts::Internal::DefaultTemplate.render, 'artifacts'] }
            .each do |rel, (seed_yaml, key)|
            existing = read_yaml(ctx[:root], rel)
            seed = YAML.safe_load(seed_yaml, aliases: false)
            result, changed = RegistryMerge.merge(existing: existing, seed: seed, entries_key: key)
            next unless changed

            write_path(ctx, rel, YAML.dump(result))
            merged << rel
          end
          merged
        end

        # --- io -----------------------------------------------------------------

        def write_if_changed(ctx, rel, contents)
          read = Owl::Storage::Api.read(path: abs(ctx[:root], rel))
          return if read.ok? && read.value == contents

          write_path(ctx, rel, contents)
          ctx[:replaced] << rel
        end

        def write_path(ctx, rel, contents)
          path = abs(ctx[:root], rel)
          return if ctx[:dry_run]

          back_up(ctx, rel, path) if ctx[:backup] && Owl::Storage::Api.exists?(path: path)
          Owl::Storage::Api.write(path: path, contents: contents)
        end

        def back_up(ctx, rel, path)
          current = Owl::Storage::Api.read(path: path)
          return if current.err?

          Owl::Storage::Api.write(path: "#{backup_dir(ctx)}/#{rel}", contents: current.value)
          ctx[:backed_up] << rel
        end

        # --- helpers ------------------------------------------------------------

        def resolve_targets(root)
          existing = Owl::Config::Api.read_key(root: root, key: 'settings.agent_targets')
          if existing.ok? && existing.value[:value].is_a?(Array) && !existing.value[:value].empty?
            return existing.value[:value].map(&:to_sym)
          end

          Owl::Skills::Internal::SeededSources::DEFAULT_TARGETS
        end

        def protected_ids(registry_result)
          return [] if registry_result.err?

          registry_result.value[:entries].select { |e| e[:managed] == false }.map { |e| e[:key] }
        end

        def id_from(rel, prefix)
          return nil unless rel.start_with?(prefix)

          rel.delete_prefix(prefix).split('/').first
        end

        def read_yaml(root, rel)
          read = Owl::Storage::Api.read(path: abs(root, rel))
          return {} if read.err?

          parsed = YAML.safe_load(read.value, aliases: false)
          parsed.is_a?(Hash) ? parsed : {}
        end

        def current_version(root)
          result = Owl::Config::Api.read_key(root: root, key: 'owl.version')
          result.ok? ? result.value[:value] : nil
        end

        def stamp_version(root)
          Owl::Config::Api.write_key(root: root, key: 'owl.version', value: Owl::VERSION)
        end

        def backup_dir(ctx)
          "#{ctx[:root]}/.owl/.backup/#{ctx[:stamp]}"
        end

        def abs(root, rel)
          "#{root}/#{rel}"
        end

        def timestamp
          Time.now.strftime('%Y%m%d-%H%M%S')
        end
      end
    end
  end
end
