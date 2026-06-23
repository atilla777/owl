# Plan: Опциональный plan-approval гейт

## Goal

Реализовать опциональный per-workflow гейт одобрения плана (`gate: plan_approved`)
по дизайну `design.md`: гейт держит шаг `implement` до явного одобрения плана;
одобрение — персистентное task-level состояние через `owl plan approve`, видимое в
`owl next` (`await_plan_approval`) и работающее headless; `reopen plan` сбрасывает
одобрение; дефолтная автономия не меняется. Документировать trade-off в
`_owl_conventions.md`. Соблюсти version-bump + CHANGELOG + 100% покрытие `api.rb`.

## Scope

- Схема workflow: добавить `gate.enum = [children_complete, plan_approved]`.
- Движок готовности: обобщить применение gate, добавить `awaiting_plan_approval`.
- Task-state: `plan_approval` + чтение/запись через слои Owl.
- Доменный API: `Owl::Tasks::Api.approve_plan` / `.plan_status`; расширить
  `Owl::Steps::Api.reopen` сбросом одобрения при reopen `plan`.
- CLI: группа `owl plan` (`approve`, `status`).
- `owl next`: `action.kind: await_plan_approval`.
- Skill/доки: `owl-orchestrator` (поведение) + `_owl_conventions.md` (trade-off).
- Версия/CHANGELOG; специи на всё новое поведение.

## Constraints

- **Back-compat**: новое поле схемы опционально; seeded workflow без гейта ведут
  себя как раньше; `owl upgrade` гейт не включает. Аддитивные изменения JSON
  (`awaiting_plan_approval`, новый `action.kind`) — bump **minor**.
- **Layering** (`docs/agents/27`): логика в `*/internal/*`, публично только
  `*/api.rb`, возврат `Result::Ok/Err`; CLI — тонкий адаптер; доступ к
  `.owl/`/`tasks/`/`docs/` только через слои.
- **Coverage** (`docs/agents/30`): 100% строк для новых/изменённых `**/api.rb`.
- **Lease-aware**: `approve_plan` уважает claim как прочие task-мутации;
  идемпотентен.
- **Constitution** (`docs/agents/23` §7.1): bump `Owl::VERSION` + `CHANGELOG.md`
  в том же коммите (затронуты `lib/**`, `schemas/**`, `skills/**`, `bin/owl`).

## Files to inspect

- `schemas/workflow.json` (step def ~:33) — добавить `gate` enum.
- `lib/owl/workflows/backends/filesystem.rb` (:295 `ready_steps`, :341
  `apply_children_gate`) — новый `apply_plan_approval_gate` + ключ результата.
- `lib/owl/workflows/internal/ready_resolver.rb` — при необходимости пробросить
  `definition_steps`/состояние одобрения.
- `lib/owl/workflows/api.rb` (`ready_steps`) — пробросить `awaiting_plan_approval`.
- `lib/owl/orchestration/internal/next_action_resolver.rb` (:23 ACTION_FIELDS,
  :56 classify) — ветка `await_plan_approval`.
- `lib/owl/tasks/api.rb` + `lib/owl/tasks/internal/` — `approve_plan`,
  `plan_status`, `PlanApproval`; чтение `content_sha` артефакта `plan`.
- `lib/owl/steps/api.rb` (:132 reopen) — сброс `plan_approval` при reopen `plan`.
- `lib/owl/cli/api.rb` (:116 dispatch, :229 task subcommands) — `dispatch_plan`.
- `lib/owl/cli/internal/commands/step_reopen.rb`, `next.rb` — образцы команд.
- `lib/owl/workflows/internal/workflow_validator.rb` (:35) — проверка
  `gate_requires_plan`.
- `skills/owl-orchestrator/SKILL.md`, `skills/_owl_conventions.md` — поведение и
  trade-off (затем `bin/owl upgrade` для `.claude/`).
- `lib/owl/version.rb`, `CHANGELOG.md`.

## Checklist

1. **Schema**: в `schemas/workflow.json` объявить step-свойство `gate` с
   `enum: ["children_complete","plan_approved"]` (опциональное). Спека на то, что
   workflow без `gate` и с каждым из значений валиден.
2. **Task-state модель**: `Owl::Tasks::Internal::PlanApproval` — чтение/запись
   top-level `plan_approval { approved, plan_sha, approved_at }` в `task.yaml`
   через существующий writer; helper `gate_open?(task, plan_artifact_sha)`.
3. **Tasks::Api.approve_plan(root:, task_id:, token: nil)**: проверить task
   существует, шаг `plan` завершён (иначе `Err(:plan_not_completed)`), lease (как
   прочие мутации; `Err(:lease_held)` при чужой живой claim), вычислить
   `plan_sha` из артефакта `plan`, записать `plan_approval`. Идемпотентно. Полное
   покрытие веток.
4. **Tasks::Api.plan_status(root:, task_id:)**: read-only `{ approved, plan_sha,
   gate_open }`.
5. **reopen-хук**: в `Owl::Steps::Api.reopen` при reopen шага `plan` (в т.ч.
   каскадно) очищать `plan_approval`. Спека.
6. **Readiness gate**: в `Filesystem#ready_steps` добавить
   `apply_plan_approval_gate` (для любого `kind`): шаги с `gate: plan_approved`
   удерживаются из `ready` в новый ключ `awaiting_plan_approval`, пока
   `PlanApproval.gate_open?` ложно. Пробросить ключ через `Workflows::Api`.
7. **next_action**: в `classify` ветка — если `awaiting_plan_approval.any?` →
   `action('await_plan_approval', task_id:, step_id: <первый удержанный>,
   blocker: <строка>)`.
8. **WorkflowValidator**: ошибка `gate_requires_plan`, если шаг объявляет
   `gate: plan_approved`, но в графе нет шага `plan`.
9. **CLI**: `dispatch_plan` в `cli/api.rb`; команды
   `Owl::Cli::Internal::Commands::PlanApprove` / `PlanStatus` (тонкие адаптеры к
   `Tasks::Api`). `owl plan approve TASK-ID [--token]`, `owl plan status TASK-ID`.
10. **Skill/доки**: в `skills/owl-orchestrator/SKILL.md` описать обработку
    `await_plan_approval` (показать план → реальный выбор approve/reopen; headless
    = стоп-точка). В `skills/_owl_conventions.md` — новый раздел про
    автономию-по-умолчанию как trade-off + как включить гейт.
11. **Version/CHANGELOG**: bump `Owl::VERSION` (minor), запись в `CHANGELOG.md`.
12. **Materialize**: `bin/owl upgrade` для синка `skills/*` в `.claude/`
    (выполнит шаг `merge_docs`/commit_push; здесь — только пометка).
13. **Тесты** (см. ниже) зелёные; `owl spec`/rspec без падений.

## Tests and verification

- `spec/owl/specs/plan_approval_gate_spec.rb` (или
  `spec/owl/workflows/api_ready_steps_plan_approval_gate_spec.rb`): гейт держит
  `implement`; `approve` открывает; idempotent + lease; reopen plan сбрасывает;
  seeded feature идёт автономно (регрессия); композит — `plan_approved` и
  `children_complete` не конфликтуют.
- `spec/owl/tasks/api_plan_approval_spec.rb`: `approve_plan` ветки (ok,
  plan_not_completed, lease_held, idempotent), `plan_status`.
- `spec/owl/cli/plan_spec.rb`: `owl plan approve` / `status` JSON-контракты.
- `spec/owl/cli/next_*`: новый `action.kind: await_plan_approval`.
- `spec/owl/workflows/.../workflow_validator_spec.rb`: `gate_requires_plan`;
  back-compat workflow без `gate`.
- Документная спека (если есть паттерн): `_owl_conventions.md` содержит раздел про
  trade-off/opt-in.
- Команда проверки: `bundle exec rspec` (учесть «red exit при 0 failures» из
  reference_owl_repo_health — смотреть на сводку, не только exit code).

## Smoke test

Во временном проекте с workflow, где у шага `implement` стоит `gate: plan_approved`:

1. Провести задачу до `plan` done.
2. `owl task ready-steps TASK --json` → `implement` в `awaiting_plan_approval`,
   не в `ready`; `owl next` → `action.kind: await_plan_approval`.
3. `owl plan approve TASK` → `ok`; `owl plan status TASK` → `gate_open: true`.
4. `owl next` → `dispatch_step` для `implement`.
5. `owl step reopen TASK plan` → `owl plan status` снова `approved:false`,
   `implement` опять удержан.
6. Контроль регрессии: та же прогонка на seeded `feature` без гейта —
   `implement` `ready` сразу после `plan`.

## Out of scope

- Глобальный (`.owl/config.yaml`) или per-task переключатель гейта (отвергнуто на
  брифе — только per-workflow).
- Гейты одобрения для других шагов, кроме привязки к плану.
- TTL/таймерный сброс одобрения.
- Включение гейта в seeded workflow по умолчанию.
- UI/диаграммная визуализация состояния одобрения (за рамками; возможный
  follow-up).
