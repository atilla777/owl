---
status: resolved
summary: "Опциональный гейт plan_approved реализован по дизайну и брифу: гейт держит implement, owl plan approve открывает его (lease-aware, идемпотентно), reopen plan сбрасывает одобрение, seeded-автономия не тронута. Полный прогон зелёный (1674 examples, 0 failures, 1 pending), 100%-гейт api.rb пройден. Одна непринципиальная находка — pre-existing rubocop ModuleLength в workflow_validator.rb стал чуть выше."
verdict: accepted_with_followups
ready: true
---

# Code review: Опциональный plan-approval гейт (`gate: plan_approved`)

## Summary

Изменение реализует опциональный per-workflow гейт одобрения плана ровно по
`design.md` и закрывает все acceptance criteria из `brief.md`:

- Новое значение существующего поля `gate` — `plan_approved` (schema enum
  `["children_complete","plan_approved"]`, поле опционально → back-compat
  сохранён).
- `Filesystem#ready_steps` получил независимый от `kind` фильтр
  `apply_plan_approval_gate`: шаги с `gate: plan_approved` уходят в новый
  аддитивный ключ `awaiting_plan_approval` (рядом с `ready` /
  `blocked_by_children`), пока `PlanApproval.gate_open?` ложно.
- Персистентное task-level состояние `plan_approval { approved, plan_sha,
  approved_at }` в `task.yaml`, привязанное к `content_sha` артефакта `plan`
  (тот же `ArtifactShaCollector`, что у step-completion).
- CLI-группа `owl plan` (`approve`, `status`) — тонкие адаптеры к
  `Owl::Tasks::Api.approve_plan` / `.plan_status`; `approve` lease-aware,
  идемпотентен, отклоняет `plan_not_completed` / `unknown_task` / `lease_held`.
- `owl next` → новый `action.kind: await_plan_approval` (поля `step_id` /
  `blocker` уже были в `ACTION_FIELDS`, новых полей не потребовалось).
- `Steps::Api.reopen` чистит `plan_approval` при reopen шага `plan` (прямом и
  каскадном).
- `WorkflowValidator` отклоняет `gate: plan_approved` без шага `plan`
  (`gate_requires_plan`); `children_complete` не тронут.
- Документация trade-off автономии и opt-in гейта добавлена в
  `_owl_conventions.md` (§9) и `owl-orchestrator/SKILL.md`.
- Соблюдены правила релиза: `Owl::VERSION` → `0.4.0`, запись в `CHANGELOG.md`,
  `Gemfile.lock` согласован.

Главный риск (регрессия дефолтной автономии) проверен и снят: при отсутствии
шагов с `gate: plan_approved` фильтр выходит сразу (`return [ready, []] if
gated_ids.empty?`), путь без гейта не меняется — это покрыто отдельным
regression-тестом.

## Findings

### 1. [Low] Pre-existing rubocop `Metrics/ModuleLength` в `workflow_validator.rb` усугублён

`lib/owl/workflows/internal/workflow_validator.rb` уже до изменения нарушал
`Metrics/ModuleLength` (226/200). Новый метод `validate_plan_gate` (+~17 строк)
поднял счётчик до 243/200. Остальные 3 offenses (`AbcSize` /
`Cyclomatic` / `Perceived` complexity на `validate_step_variants`) —
pre-existing и этим изменением не затронуты. RuboCop не входит в тест-гейт
проекта (гейт — только 100% покрытие `api.rb`), поэтому это не блокер. Внесено в
follow-ups.

### 2. [Info] Имена spec-файлов отличаются от перечисленных в брифе

Бриф/план ссылались на `spec/owl/specs/plan_approval_gate_spec.rb` и т.п.;
фактические специи лежат по другим (осмысленным, доменно-сгруппированным) путям
(`spec/owl/workflows/api_ready_steps_plan_approval_gate_spec.rb`,
`spec/owl/tasks/api_plan_approval_spec.rb`, `spec/owl/cli/plan_spec.rb`,
`spec/owl/workflows/internal/workflow_validator_plan_gate_spec.rb`,
`spec/owl/docs/conventions_plan_approval_spec.rb`). Покрытие всех сценариев
брифа полное; функционального расхождения нет.

### 3. [Info] Дополнительный код ошибки `plan_artifact_missing`

`PlanApproval.finalize_approval` возвращает `plan_artifact_missing`, если у
завершённого `plan` нет единого `content_sha`. В `design.md` он не перечислен,
но это защитная ветка (internal-слой, не `api.rb`), разумная и не ломает
контракт.

## Resolution

Все находки — низкой/информационной значимости; блокеров нет. Реальных багов в
логике гейта, lease-модели, сбросе одобрения и регрессионном пути не обнаружено,
правок кода в рамках ревью не вносилось. Объективная проверка (полный прогон
rspec + rubocop по затронутым файлам + точечный smoke CLI) выполнена и
зафиксирована в `verification.md`. Вердикт — `accepted_with_followups`:
функциональность принимается, единственный реальный остаток — pre-existing
rubocop ModuleLength (находка 1) — вынесен в follow-up.

## Remediation

- Не требуется в рамках этой задачи. См. Residual risks / follow-up по
  `ModuleLength`.

## Residual risks

- `workflow_validator.rb` остаётся выше лимита `Metrics/ModuleLength`
  (243/200). Рекомендуемый follow-up: вынести группу `validate_*`-методов в
  отдельный internal-модуль, чтобы убрать pre-existing offense (по возможности
  заодно `validate_step_variants` complexity). Низкий приоритет, вне контракта
  данной задачи.
- `gate_requires_plan` проверяет наличие шага `plan`, но не шага-носителя
  `implement` (гейт можно повесить на любой шаг — это by design в `design.md`
  §8); риск отсутствует, отмечено для полноты.
