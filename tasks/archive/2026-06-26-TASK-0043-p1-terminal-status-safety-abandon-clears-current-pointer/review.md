---
status: resolved
summary: >-
  Реализация терминальной безопасности задач корректна, полностью покрыта
  тестами и соответствует AC brief; отклонение по семантике `archived`
  (mid-flow не отвергается) проверено и принято. Verdict accepted_with_followups.
verdict: accepted_with_followups
ready: true
---

# Review

## Summary

Отревьюен диф TASK-0043 (workflow `hotfix`, bug-fix «terminal-status safety»,
`Owl::VERSION` 0.22.1 → 0.23.0) против AC brief, API-секции design и чеклиста
plan. Реализация делает терминальный статус задачи единообразно безопасным:
`abandon` чистит current-указатель (паритет с `delete`); явный доступ к мёртвой
задаче через `next`/`status`/`ready-steps`/`instructions` отдаёт структурную
ошибку `task_terminal` с ненулевым exit; `owl next` без аргумента при
терминальном указателе тихо проваливается в `auto_select`; задачный
`TERMINAL_STATUSES` сведён к единому `Tasks::Internal::TaskStatuses::TERMINAL`.

Все 17 затронутых файлов проходят слойность Backend/Internal/Api (статус задачи
читается через `Tasks::Api.inspect`, без прямого FS-доступа из оркестрации/CLI).
Независимая верификация ревьюера зелёная: `bundle exec rspec` → 2027 examples,
0 failures, 1 pending; `bundle exec rubocop` по 12 изменённым lib-файлам → no
offenses; `lib/owl/**/api.rb` (+ `result.rb`) сохраняют 100% line coverage
(SimpleCov-гейт `spec_helper.rb` не выдал ни одного файла ниже 100%).

**Verdict: `accepted_with_followups`** — изменение fit-to-ship; зафиксирован один
не-блокирующий follow-up про сигнал завершения доставки (см. Remediation).

## Findings

- [x] **F1 (центральный judgment-call — ОТКЛОНЕНИЕ от буквы brief по `archived`/`done`): ПРИНЯТО.**
  Brief AC требовал отвергать ЛЮБОЙ явный терминальный id, включая `archived`/`done`.
  Имплементер сузил правило: `archived`/`done` отвергаются (guard + fallback)
  ТОЛЬКО когда workflow реально завершён (все шаги `done`/`skipped`); `abandoned`
  отвергается всегда. Проверка claim по инспекции:
  - `archive` ДЕЙСТВИТЕЛЬНО выставляет статус `archived` ДО `commit_push`:
    `archived_task_writer.rb:8` (`STATUS = 'archived'`), а порядок шагов во всех
    seeded delivery-workflow — `... archive → commit_push`
    (`.owl/workflows/hotfix/workflow.yaml`: `review_code → merge_docs → archive →
    commit_push`; идентично `feature`). Подтверждено grep'ом по `id:`.
  - `commit_push` действительно драйвится через `owl next TASK-X` (явный id):
    orchestrator SKILL шаг 7 + 60 — «terminal step is `commit_push`, runs *after*
    `archive`», диспатчится как обычный ready-шаг.
  - Поэтому буквальный reject-all-archived ломал бы переход `archive →
    commit_push` в КАЖДОЙ доставке. Отклонение обосновано.
  - Предикат `TerminalStatus.orchestration_terminal?` (`terminal_status.rb:30`)
    корректно различает «archived-but-incomplete» (mid-flow, `commit_push`
    pending → `workflow_complete?` false → НЕ терминал) и «archived-and-complete»
    (все шаги done/skipped → терминал). `abandoned` — безусловный `return true`
    ДО проверки шагов. Пустой список шагов → `false` (не считается завершённым).
  - Покрыто прямыми тестами: `terminal_status_spec.rb` (archived mid-flow→false,
    archived all-done→true, abandoned→true, done-complete→true, no-steps→false,
    nil→false) и e2e `task_terminal_guard_spec.rb` («still dispatches commit_push
    for an archived task whose workflow is mid-flow» — реально прогоняет
    work→archive→commit_push и проверяет `dispatch_step commit_push`).
  Это не просто инспекция — отклонение защищено регресс-тестом. **ACCEPT.**

- [x] **F2 (shared `TERMINAL_STATUSES`): корректно.** `availability_scanner.rb` и
  `ready_scanner.rb` оба присваивают `TERMINAL_STATUSES = TaskStatuses::TERMINAL`
  (та же замороженная константа). `task_statuses_spec.rb` проверяет identity
  через `be(...)`, состав `%w[archived abandoned done]`, и что шаговый
  `completion_gate::TERMINAL_STATUSES` (`%w[done skipped]`) — отдельное понятие
  (`not_to eq`). `completion_gate.rb:25` не тронут. Поведение фильтрации сканеров
  не изменилось (состав идентичен прежним локальным спискам).

- [x] **F3 (abandon чистит указатель, обе ветки): корректно.**
  `abandon_writer.rb:38` — `CurrentResetter.reset_if_matches` стоит ДО
  идемпотентного early-return (строка 41), значит повторный abandon уже-abandoned
  задачи всё равно чинит протухший указатель. Покрыто 3 тестами в
  `api_abandon_spec.rb`: current→чистит, non-current→не трогает, idempotent→чинит.
  Замечание по реализации vs design: design предлагал вставить reset в `persist`;
  имплементер поставил в `locked_call` перед early-return — это ЛУЧШЕ, т.к.
  `persist` не вызывается в early-return ветке, а требование brief именно про
  идемпотентный путь. Отклонение в плюс, принято.

- [x] **F4 (`task_terminal` → ненулевой CLI exit): корректно.** Guard в
  `task_support.rb:reject_if_terminal` возвращает `JsonPrinter.failure(...)` (exit
  1). E2e `task_terminal_guard_spec.rb` проверяет `exit_code != 0`, `stdout == ''`,
  `error.code == 'task_terminal'`, `error.details.task_id` для всех 4 команд.

- [x] **F5 (явный vs неявный резолв): корректно.** Guard срабатывает только при
  непустом `task_id` (`return nil if task_id.nil? || empty`); неявный резолв из
  current-указателя обрабатывается тихим fallback в `task_resolver.rb:from_current`
  (`return auto_select if terminal?`). Read-Err (`task_not_found`) → guard отдаёт
  `nil`, нормальный путь команды сам surface'ит ошибку (тест «propagates the
  underlying Err for an unknown task» + «does not reject an explicit LIVE task id»).

- [x] **F6 (CHANGELOG + VERSION): присутствуют.** `version.rb` 0.22.1→0.23.0
  (minor — новый код ошибки/поведение, back-compat add на ранее-некорректном
  пути; согласуется с Constitution §7.1). `CHANGELOG.md` — секция `[0.23.0]` с
  Added/Fixed/Changed, явно документирует отклонение по `archived` mid-flow.

## Resolution

Все F1–F6 проверены и закрыты в этой ветке (статусы `[x]`). Блокеров нет.
`status: resolved`. Один не-блокирующий follow-up вынесен в Remediation.

## Remediation

- **FU-1 (follow-up, не блокер): сигнал завершения доставки.** Новый guard
  применяется к `next`/`ready-steps` по ЯВНОМУ id и срабатывает на
  archived-and-complete задаче. После того как `commit_push` завершён (статус
  `archived` + все шаги done), повторный `owl next TASK-X` теперь возвращает
  `task_terminal` (ok:false), тогда как раньше отдавал `action.kind: done`
  (`next_action_resolver.rb:73`, `all_steps_done?` — независимо от статуса). Тот
  же эффект у `owl task ready-steps TASK-X`. Т.е. для всех seeded delivery-
  workflow путь `done`/«ready-steps пуст» по явному id после доставки заменяется
  ошибкой `task_terminal`. Это РОВНО буква brief AC (явный терминальный id →
  `task_terminal`) и orchestrator всё равно останавливает прогон после
  терминального `commit_push` (SKILL шаг 7/9 знают терминальный шаг статически),
  поэтому регрессии тестов нет (2027 зелёных). Но orchestrator SKILL по-прежнему
  документирует `done` как путь штатного завершения, который теперь затенён для
  archived-задач. Рекомендация для будущей задачи: либо явно описать в
  orchestrator-skill, что `task_terminal` по уже-доставленной задаче = «уже
  завершено, штатный финальный отчёт» (а не stop-condition «CLI error»), либо
  оставить `done` достижимым для полностью-завершённой задачи. Решение — за
  человеком; на доставку TASK-0043 не влияет.

## Residual risks

- **Будущий статус задачи `done`.** Сейчас ни один поток не пишет задачный
  `done` (это TASK-0044, авто-закрытие на финальном шаге). Логика
  forward-compatible: `done` + завершённый workflow → терминал; правьте FU-1
  вместе с TASK-0044, т.к. именно `done` сделает `action.kind: done` по явному id
  недостижимым штатно.
- **Пустой список шагов у терминальной задачи.** `workflow_complete?` для
  `steps == []` возвращает `false` (задача НЕ считается терминальной для
  orchestration). Это сознательно (нельзя «завершить» воркфлоу без шагов), но
  означает, что archived-задача без записанных шагов осталась бы runnable для
  явного `next`. В seeded-воркфлоу шаги всегда есть, поэтому практического
  риска нет; зафиксировано как известное поведение (покрыто тестом «false for a
  terminal task carrying no steps»).
- **Многосессионность.** Очистка current-указателя — локальное per-clone
  состояние (`.owl/local/`), гонок между клонами не вносит. Без изменений.
