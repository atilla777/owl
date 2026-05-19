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

            settings:
              language:
                communication: en

              storage:
                backend: filesystem

                roles:
                  tasks: "{{project.root}}/tasks"
                  docs: "{{project.root}}/docs"
                  archive: "{{project.root}}/tasks/archive"

              workflows:
                enabled: []
          YAML
        end
      end
    end
  end
end
