# frozen_string_literal: true

module Owl
  module Artifacts
    module Internal
      module SeededSources # rubocop:disable Metrics/ModuleLength
        module_function

        def keys
          SOURCES.keys
        end

        def files
          SOURCES.flat_map do |key, payload|
            [
              {
                relative_path: ".owl/artifacts/#{key}/artifact.yaml",
                contents: payload[:artifact_yaml]
              },
              {
                relative_path: ".owl/artifacts/#{key}/templates/default.md",
                contents: payload[:default_template]
              }
            ]
          end
        end

        BRIEF_YAML = <<~YAML
          id: brief
          title: Brief
          kind: markdown
          description: Краткое описание фичи — контекст, цель, критерии готовности.
          default_template: templates/default.md

          front_matter:
            type: object
            required: [status, summary]
            properties:
              status:
                type: string
                enum: [draft, approved]
              summary:
                type: string

          validation:
            required_sections:
              - Контекст
              - Цель
              - Acceptance criteria
        YAML

        BRIEF_TEMPLATE = <<~MARKDOWN
          ---
          status: draft
          summary: TODO — one-line summary of the feature.
          ---

          # Brief

          ## Контекст

          TODO

          ## Цель

          TODO

          ## Acceptance criteria

          - TODO
        MARKDOWN

        SPEC_YAML = <<~YAML
          id: spec
          title: Specification
          kind: markdown
          description: Спецификация фичи / задачи — intent, AC, scope, ограничения.
          default_template: templates/default.md

          front_matter:
            type: object
            required: [status, summary]
            properties:
              status:
                type: string
                enum: [draft, approved]
              summary:
                type: string

          validation:
            required_sections:
              - Intent
              - Acceptance criteria
              - Non-goals
              - Open questions
              - Scope
        YAML

        SPEC_TEMPLATE = <<~MARKDOWN
          ---
          status: draft
          summary: TODO — one-line summary of the spec.
          ---

          ## Intent

          TODO

          ## Acceptance criteria

          - TODO

          ## Non-goals

          - TODO

          ## Open questions

          - TODO

          ## Scope

          TODO
        MARKDOWN

        DESIGN_YAML = <<~YAML
          id: design
          title: Design
          kind: markdown
          description: Design notes — контекст, выбранное решение, альтернативы, риски.
          default_template: templates/default.md

          validation:
            required_sections:
              - Контекст
              - Решение
              - Альтернативы
              - Риски
        YAML

        DESIGN_TEMPLATE = <<~MARKDOWN
          # Design

          ## Контекст

          TODO

          ## Решение

          TODO

          ## Альтернативы

          - TODO

          ## Риски

          - TODO
        MARKDOWN

        DECOMPOSITION_YAML = <<~YAML
          id: decomposition
          title: Decomposition
          kind: markdown
          description: Декомпозиция composite task на child tasks — цель, список детей, порядок исполнения.
          default_template: templates/default.md

          validation:
            required_sections:
              - Цель
              - Дочерние задачи
              - Порядок исполнения
        YAML

        DECOMPOSITION_TEMPLATE = <<~MARKDOWN
          # Decomposition

          ## Цель

          TODO

          ## Дочерние задачи

          - TODO

          ## Порядок исполнения

          1. TODO
        MARKDOWN

        TASKS_YAML = <<~YAML
          id: tasks
          title: Tasks checklist
          kind: markdown
          description: Implementation checklist — список шагов реализации внутри одной задачи.
          default_template: templates/default.md

          validation:
            required_sections:
              - Цель
              - Чеклист
        YAML

        TASKS_TEMPLATE = <<~MARKDOWN
          # Tasks

          ## Цель

          TODO

          ## Чеклист

          - [ ] TODO
        MARKDOWN

        VERIFICATION_YAML = <<~YAML
          id: verification
          title: Verification report
          kind: markdown
          description: Verification report — список выполненных команд, результаты, найденные проблемы.
          default_template: templates/default.md

          front_matter:
            type: object
            required: [status, summary]
            properties:
              status:
                type: string
                enum: [passed, failed, partial]
              summary:
                type: string

          validation:
            required_sections:
              - Summary
              - Commands
              - Outcomes
        YAML

        VERIFICATION_TEMPLATE = <<~MARKDOWN
          ---
          status: passed
          summary: TODO — one-line verification summary.
          ---

          ## Summary

          TODO

          ## Commands

          - `TODO`

          ## Outcomes

          - TODO
        MARKDOWN

        ISSUE_YAML = <<~YAML
          id: issue
          title: Issue report
          kind: markdown
          description: Описание инцидента для hotfix — что сломалось, симптомы, воздействие, затронутые версии.
          default_template: templates/default.md

          validation:
            required_sections:
              - Описание
              - Симптомы
              - Воздействие
              - Затронутые версии
        YAML

        ISSUE_TEMPLATE = <<~MARKDOWN
          # Issue

          ## Описание

          TODO

          ## Симптомы

          - TODO

          ## Воздействие

          TODO

          ## Затронутые версии

          - TODO
        MARKDOWN

        PATCH_PLAN_YAML = <<~YAML
          id: patch_plan
          title: Patch plan
          kind: markdown
          description: План фикса для hotfix — контекст, шаги фикса, тестирование, откат.
          default_template: templates/default.md

          validation:
            required_sections:
              - Контекст
              - План фикса
              - Тесты
              - Откат
        YAML

        PATCH_PLAN_TEMPLATE = <<~MARKDOWN
          # Patch plan

          ## Контекст

          TODO

          ## План фикса

          1. TODO

          ## Тесты

          - TODO

          ## Откат

          TODO
        MARKDOWN

        RESEARCH_FINDINGS_YAML = <<~YAML
          id: research_findings
          title: Research findings
          kind: markdown
          description: Результаты исследования — вопрос, собранные данные, выводы.
          default_template: templates/default.md

          validation:
            required_sections:
              - Вопрос
              - Данные
              - Выводы
        YAML

        RESEARCH_FINDINGS_TEMPLATE = <<~MARKDOWN
          # Findings

          ## Вопрос

          TODO

          ## Данные

          - TODO

          ## Выводы

          - TODO
        MARKDOWN

        RECOMMENDATION_YAML = <<~YAML
          id: recommendation
          title: Recommendation
          kind: markdown
          description: Рекомендация по итогам исследования — вопрос, рекомендация, обоснование, альтернативы.
          default_template: templates/default.md

          validation:
            required_sections:
              - Вопрос
              - Рекомендация
              - Обоснование
              - Альтернативы
        YAML

        RECOMMENDATION_TEMPLATE = <<~MARKDOWN
          # Recommendation

          ## Вопрос

          TODO

          ## Рекомендация

          TODO

          ## Обоснование

          TODO

          ## Альтернативы

          - TODO
        MARKDOWN

        SOURCES = {
          'brief' => { artifact_yaml: BRIEF_YAML, default_template: BRIEF_TEMPLATE },
          'spec' => { artifact_yaml: SPEC_YAML, default_template: SPEC_TEMPLATE },
          'design' => { artifact_yaml: DESIGN_YAML, default_template: DESIGN_TEMPLATE },
          'decomposition' => { artifact_yaml: DECOMPOSITION_YAML, default_template: DECOMPOSITION_TEMPLATE },
          'tasks' => { artifact_yaml: TASKS_YAML, default_template: TASKS_TEMPLATE },
          'verification' => { artifact_yaml: VERIFICATION_YAML, default_template: VERIFICATION_TEMPLATE },
          'issue' => { artifact_yaml: ISSUE_YAML, default_template: ISSUE_TEMPLATE },
          'patch_plan' => { artifact_yaml: PATCH_PLAN_YAML, default_template: PATCH_PLAN_TEMPLATE },
          'research_findings' => { artifact_yaml: RESEARCH_FINDINGS_YAML,
                                   default_template: RESEARCH_FINDINGS_TEMPLATE },
          'recommendation' => { artifact_yaml: RECOMMENDATION_YAML, default_template: RECOMMENDATION_TEMPLATE }
        }.freeze
      end
    end
  end
end
