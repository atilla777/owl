# frozen_string_literal: true

module Owl
  module Config
    module Internal
      module DefaultTemplate
        module_function

        def render(project_id:)
          <<~YAML
            schema_version: 1

            project:
              id: #{project_id}
              title: #{project_id}
              root: "{{cwd}}"

            owl:
              control_root: "{{project.root}}/.owl"

            workflow:
              default: feature

            storage:
              active_profile: default

              profiles:
                default:
                  backend: filesystem

                  roles:
                    control:
                      path: "{{project.root}}/.owl"

                    local_state:
                      path: "{{project.root}}/.owl/local"

                    index:
                      path: "{{project.root}}/tasks/index.yaml"

                    tasks:
                      path: "{{project.root}}/tasks"

                    archive:
                      path: "{{project.root}}/tasks/archive"

                    docs:
                      path: "{{project.root}}/docs"

                    specs:
                      path: "{{project.root}}/specs"

            settings:
              language:
                communication: en

              storage:
                backend: filesystem

                roles:
                  tasks: "{{project.root}}/tasks"
                  docs: "{{project.root}}/docs"
                  archive: "{{project.root}}/tasks/archive"
                  specs: "{{project.root}}/specs"

              workflows:
                enabled: []

              # Optional: objective verification gate. When `command` is set, a
              # step flagged `verify: true` (the seeded `review_code` step) runs
              # it at `owl step complete`, authors verification.md from the exit
              # code, and blocks completion unless it passes. Left unset =>
              # gate inactive (fail-open with a warning).
              # verification:
              #   command: "bundle exec rspec"
              #   timeout_seconds: 1800

            # Optional: explicit overlay paths per workflow step. The convention
            # paths .owl/overlays/<step>.md and docs/ai/<step>.md are auto-
            # discovered; this block lets you point at additional files.
            # context_overlays:
            #   design:
            #     - docs/architecture/coding-conventions.md
            #   commit_push:
            #     - docs/ai/git-conventions.md
          YAML
        end
      end
    end
  end
end
