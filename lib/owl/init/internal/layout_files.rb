# frozen_string_literal: true

require_relative '../../artifacts/api'
require_relative '../../config/api'
require_relative '../../skills/api'
require_relative '../../workflows/api'
require_relative 'overlay_template'

module Owl
  module Init
    module Internal
      module LayoutFiles
        OVERLAY_STEPS = %w[
          brief design plan implement review_code merge_docs archive commit_push
        ].freeze

        # Session-level overlay keys are NOT workflow steps: they shape
        # cross-step, human-facing output. `orchestrator` is applied to the
        # orchestrator's end-of-run completion report (see `_owl_conventions.md`
        # §8 and `owl overlay show orchestrator`).
        SESSION_OVERLAYS = %w[orchestrator].freeze

        module_function

        def call(root:, project_id:, agent_targets: Owl::Skills::Internal::SeededSources::DEFAULT_TARGETS)
          # `preserve_if_exists` marks user/project STATE that a forced re-run
          # (`owl init --force`, used to refresh materialised skills/commands)
          # must never clobber: the config (settings like language), the two
          # registries (which carry project-owned, non-managed workflow/artifact
          # registrations), and the task index. On a first init these files do
          # not exist yet and are created normally; only the *seed bodies*
          # (skills, commands, workflow/artifact source files below) are
          # refreshable and get overwritten by `--force`.
          base = [
            { path: "#{root}/.owl/config.yaml",
              contents: Owl::Config::Api.default_template(project_id: project_id),
              preserve_if_exists: true },
            { path: "#{root}/.owl/workflows.yaml",
              contents: Owl::Workflows::Api.default_template,
              preserve_if_exists: true },
            { path: "#{root}/.owl/artifacts.yaml",
              contents: Owl::Artifacts::Api.default_template,
              preserve_if_exists: true },
            { path: "#{root}/tasks/index.yaml",
              contents: tasks_index_template,
              preserve_if_exists: true },
            { path: "#{root}/docs/.keep",
              contents: '' }
          ]

          # Project-authored overlay content is likewise preserved across a
          # forced re-run: overlays are scaffolded with a default template on
          # first init, but a re-run must NOT clobber project customizations.
          overlays = (OVERLAY_STEPS + SESSION_OVERLAYS).map do |step|
            { path: "#{root}/.owl/overlays/#{step}.md",
              contents: OverlayTemplate.for_step(step_id: step),
              preserve_if_exists: true }
          end

          base + overlays \
               + seeded_files(root: root, sources: Owl::Workflows::Api.seeded_sources) \
               + seeded_files(root: root, sources: Owl::Artifacts::Api.seeded_sources) \
               + seeded_files(root: root, sources: Owl::Skills::Api.seeded_sources(targets: agent_targets))
        end

        def seeded_files(root:, sources:)
          sources.map do |file|
            { path: "#{root}/#{file[:relative_path]}", contents: file[:contents] }
          end
        end

        def tasks_index_template
          <<~YAML
            schema_version: 1

            tasks: []
          YAML
        end
      end
    end
  end
end
