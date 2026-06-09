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

        module_function

        def call(root:, project_id:, agent_targets: Owl::Skills::Internal::SeededSources::DEFAULT_TARGETS)
          base = [
            { path: "#{root}/.owl/config.yaml",
              contents: Owl::Config::Api.default_template(project_id: project_id) },
            { path: "#{root}/.owl/workflows.yaml",
              contents: Owl::Workflows::Api.default_template },
            { path: "#{root}/.owl/artifacts.yaml",
              contents: Owl::Artifacts::Api.default_template },
            { path: "#{root}/tasks/index.yaml",
              contents: tasks_index_template },
            { path: "#{root}/docs/.keep",
              contents: '' }
          ]

          # `preserve_if_exists` keeps project-authored overlay content across a
          # forced re-run (`owl init --force`): overlays are scaffolded with a
          # default template on first init, but a re-run must NOT clobber any
          # customizations the project added. Other layout files are still
          # overwritten by `--force`.
          overlays = OVERLAY_STEPS.map do |step|
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
