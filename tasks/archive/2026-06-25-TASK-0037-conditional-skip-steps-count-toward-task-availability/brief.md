---
status: approved
summary: "Auto-select/claim --next пропускают задачу, чьё единственное продвигающее действие — conditional-skip (when=false шаг): AvailabilityScanner считает available только по value[:ready], а conditional_skip шаги туда не входят. Но owl next (с явной/current задачей) такую задачу продвигает через skip_conditional_step. Считать задачу available, если есть ready ИЛИ conditional_skip шаг."
---

# Problem

TASK-0028 добавил условные шаги (`when:` предикат): шаг с ложным предикатом
держится вне `ready` и попадает в отдельный bucket `conditional_skip` результата
`Workflows::Api.ready_steps`. `next_action_resolver` обрабатывает его ПЕРЕД `ready`
(`if conditional.any? → skip_conditional_action; elsif ready.any? → dispatch`), то
есть задача с conditional_skip шагом **продвигаема**: `owl next` вернёт действие
`skip_conditional_step`, оркестратор сделает `owl step skip`, разблокировав зависимые.

Но **auto-select** этого не знает. `AvailabilityScanner.build_candidate` гейтит
доступность по `ready_step_ids`, которые берут ТОЛЬКО `value[:ready]`:
`return nil if ready_ids.empty?`. Если у задачи единственное ближайшее действие —
conditional-skip (а `ready` пуст), она НЕ попадает в `available` → `owl next` без
current-указателя и `owl task claim --next` её **пропускают**. Задача «застревает»
для авто-выбора, хотя при явном указании оркестратор её продвинул бы.

Это рассинхрон task-level авто-выбора (по `ready`) и step-level условной логики
(`conditional_skip` — тоже продвигающее действие).

# Goal

Считать задачу доступной для авто-выбора, если у неё есть **ready ИЛИ
conditional_skip** шаг (оба — продвигающие действия: dispatch либо skip). Тогда
`owl next`/`claim --next` подхватывают задачу, чьё следующее действие — авто-skip
условного шага, и оркестратор её продвигает. Поведение для задач с обычным `ready`
шагом не меняется.

# Scenarios

### Requirement: conditional-skip шаг делает задачу доступной

The system SHALL treat a task as available when its only actionable step is a
`conditional_skip` step.

#### Scenario: задача с только conditional_skip авто-выбирается
- WHEN у задачи нет `ready` шагов, но есть `conditional_skip` шаг (предикат `when:`
  ложен), и задача не заклеймлена
- THEN `AvailabilityScanner`/`owl task available` включает её в выдачу
- AND `owl next` без current-указателя / `owl task claim --next` подхватывают её
  (оркестратор продвинет через `skip_conditional_step`)

### Requirement: обычная доступность не регрессирует

The system SHALL keep existing availability behavior for tasks with ready steps.

#### Scenario: задача без ready и без conditional_skip недоступна
- WHEN у задачи нет ни `ready`, ни `conditional_skip` шагов (всё заблокировано
  детьми/планом/зависимостями)
- THEN она НЕ available (как сейчас)

#### Scenario: задача с ready шагом — без изменений
- WHEN у задачи есть `ready` шаг
- THEN она available как прежде (порядок/сортировка не меняются)

# Edge cases

- **Actionable = ready ∪ conditional_skip.** Доступность гейтить по объединению.
  `blocked_by_children`/`awaiting_plan_approval` НЕ делают задачу available (это
  ожидание, не действие) — их не включать.
- **deps-aware пересечение.** `ReadyAvailabilityScanner` (TASK-0030) пересекает
  available с deps+status-ready set; conditional-only задача, прошедшая deps+status,
  должна остаться в пересечении (её task_id есть в available → попадёт, если deps ок).
- **candidate_hash[:ready_step_ids].** Сейчас несёт `ready` ids. Решить: оставить
  только `ready` (информативно) или класть actionable. Достаточно гейтить доступность
  по actionable; что класть в hash — выбрать так, чтобы не сломать потребителей
  (`claim_service` читает только `:task_id`).
- **Скан без лишних вызовов.** `ready_steps` уже зовётся один раз на задачу; брать из
  того же результата оба bucket'а (`ready` + `conditional_skip`), без второго вызова.
- **Версионирование.** Изменение поведения авто-выбора → minor bump VERSION +
  CHANGELOG.

# Acceptance criteria

- [ ] `AvailabilityScanner` считает задачу available, если есть `ready` ИЛИ
  `conditional_skip` шаг (из одного вызова `ready_steps`).
- [ ] `owl next` без current / `owl task claim --next` подхватывают conditional-only
  задачу; deps-aware пересечение (`ReadyAvailabilityScanner`) её сохраняет.
- [ ] Задача без ready и без conditional_skip остаётся недоступной; задача с ready —
  без изменений (сортировка/поведение те же).
- [ ] Регрессионные тесты: conditional-only → available; нет actionable → не available;
  ready → как прежде.
- [ ] rspec зелёный; 100% покрытие тронутых `**/api.rb`; RuboCop net-zero; minor bump
  VERSION + CHANGELOG.
