---
status: approved
summary: "AvailabilityScanner: ready_step_ids → actionable_step_ids (ready ∪ conditional_skip из одного ready_steps); build_candidate/candidate_hash используют actionable. Тест conditional-only → available. minor bump 0.19.0→0.20.0."
---

# Goal

Считать задачу доступной по actionable = ready ∪ conditional_skip, чтобы auto-select/
claim --next подхватывали задачу, чьё единственное действие — авто-skip условного шага.

# Scope

- `lib/owl/tasks/internal/availability_scanner.rb` — `ready_step_ids` →
  `actionable_step_ids`; `build_candidate`/`candidate_hash` под actionable.
- `lib/owl/version.rb` + `CHANGELOG.md` — minor bump 0.19.0 → 0.20.0.

# Constraints

- Один вызов `ready_steps` на задачу (оба bucket'а из одного результата).
- `blocked_by_children`/`awaiting_plan_approval` НЕ делают задачу available.
- Ready-задачи: поведение/сортировка без изменений.
- Не менять `ReadyAvailabilityScanner`/`ReadyScanner`/`next_action_resolver`
  (резолвер уже умеет conditional_skip; deps-пересечение сохранит conditional-only
  задачу автоматически).
- 100% покрытие тронутых `**/api.rb`; RuboCop net-zero; rspec зелёный.
- Constitution §7.1: minor bump VERSION + CHANGELOG.

# Files to inspect

- `lib/owl/tasks/internal/availability_scanner.rb` (`build_candidate`,
  `candidate_hash`, `ready_step_ids`).
- `lib/owl/workflows/backends/filesystem.rb` (форма `conditional_skip: [{id, reason}]`).
- `lib/owl/orchestration/internal/next_action_resolver.rb` (подтвердить: conditional
  → skip_conditional_action перед ready — менять НЕ надо).
- спек(и) availability / `owl task available` — куда добавить conditional-only тест.
- `spec/owl/tasks/internal/*availability*` или `spec/owl/tasks/api_*` (available).

# Checklist

- [ ] Переименовать `ready_step_ids` → `actionable_step_ids`; вернуть
      `ready_ids + conditional_ids` (`Array(value[:ready]).map{:id}` +
      `Array(value[:conditional_skip]).map{:id}`).
- [ ] `build_candidate`: `actionable = actionable_step_ids(...); return nil if
      actionable.empty?`.
- [ ] `candidate_hash`: `ready_step_ids: actionable` (+ комментарий, что поле теперь
      = actionable = ready ∪ conditional_skip).
- [ ] `CHANGELOG.md` (Changed): auto-select/claim --next теперь считают задачу
      доступной, если её ближайшее действие — conditional-skip (when=false шаг), а не
      только ready; устранён рассинхрон task-level авто-выбора и step-level условной
      логики. owl task available тоже включает такие задачи.
- [ ] `lib/owl/version.rb`: 0.19.0 → 0.20.0.

# Tests and verification

- [ ] Conditional-only: задача с `when:`-ложным шагом (ready пуст, conditional_skip
      непуст) → присутствует в `AvailabilityScanner.scan` / `owl task available`.
- [ ] Нет actionable (только blocked_by_children/awaiting_plan/ничего) → НЕ available.
- [ ] Ready-шаг → available как прежде (регрессия; сортировка/поля не сломаны).
- [ ] (Желательно) `owl next` без current на conditional-only задаче → action
      `skip_conditional_step` (интеграция: подтверждает сквозной путь).
- [ ] `bundle exec rspec` зелёный, 0 failures; покрытие `**/api.rb` без регрессий.
- [ ] `bundle exec rubocop lib/owl/tasks/internal/availability_scanner.rb` net-zero.

# Smoke test

```
# workflow с условным шагом (when artifact not_matches ...), задача без ready,
# но с conditional_skip → owl task available её показывает; owl next → skip_conditional_step
owl task available --json   # содержит conditional-only задачу
```

# Out of scope

- Изменение conditional-логики движка (TASK-0028) / next_action_resolver.
- deps-пересечение (ReadyAvailabilityScanner) — не трогаем.
- P3 / F2.2.
