---
status: approved
summary: "owl commit-push делает git add -A (весь tree), утаскивая в коммит доставки каталоги ДРУГИХ активных задач (со-существующий backlog). Сделать staging scoped: исключать tasks/<other-id>/ незавершённых задач, сохранив доставку текущей (код/доки/архив/индекс)."
---

# Problem

`owl commit-push` стейджит весь рабочий tree через `git add -A`
(`GitRunner#add_all` → `Transaction#stage_and_guard`/`flip_done`). При наличии
**со-существующего backlog** (другие активные задачи в `tasks/<TASK-ID>/`,
ещё не доставленные) их файлы попадают в коммит текущей доставки.

Это реально мешало в прошлых волнах: приходилось вручную временно убирать
backlog-задачи из `tasks/`, делать commit-push, затем возвращать. `git add -A`
небезопасен, когда в дереве сосуществуют незавершённые задачи.

Дополнительно `git add -A` означает: текущие проверки транзакции
(`nothing_to_commit`-guard и `retry?`-идемпотентность) опираются на
«весь рабочий tree чист» (`git status --porcelain` пуст). При backlog в дереве
всегда есть неотслеженные `?? tasks/TASK-*` — поэтому «tree чист» никогда не
истинно, что ломает и пустую-доставку-guard, и идемпотентный retry после
неудачного push.

# Goal

Сделать staging в `owl commit-push` **scoped**: стейджить доставку текущей
задачи (изменения кода, docs/, заархивированную текущую задачу, индекс,
version/CHANGELOG), но **исключать каталоги других активных задач**
(`tasks/<id>/`, где `id` активна и `id != task_id`). Транзакционные инварианты
(пустая доставка → `nothing_to_commit`; идемпотентный retry после push-fail)
должны сохраняться при наличии backlog.

# Scenarios

### Requirement: commit-push не включает чужие активные задачи

The system SHALL exclude other active tasks' directories from the staged
delivery.

#### Scenario: backlog не попадает в коммит
- WHEN выполняется `owl commit-push <T>` при наличии другой активной задачи
  `O` с неотслеженным/изменённым каталогом `tasks/<O>/`
- THEN коммит доставки `T` НЕ содержит файлов `tasks/<O>/`
- AND доставка `T` (код, docs/, архив `T`, индекс, version/CHANGELOG)
  закоммичена полностью

#### Scenario: quick-доставка текущей задачи включается
- WHEN текущая задача `T` ещё активна и лежит в `tasks/<T>/` (workflow без шага
  archive перед commit_push, напр. quick) и нет других активных задач кроме `T`
- THEN каталог `tasks/<T>/` стейджится и попадает в коммит (его не исключают,
  т.к. это текущая задача)

### Requirement: инварианты транзакции при backlog

The system SHALL keep the empty-delivery guard and idempotent retry correct
when an unrelated active task is present in the working tree.

#### Scenario: пустая доставка при backlog
- WHEN после scoped-staging в индексе нет изменений (доставка пуста), но в дереве
  присутствует неотслеженный backlog `tasks/<O>/`
- THEN команда возвращает `nothing_to_commit` (а не пытается создать пустой
  коммит), шаг остаётся `running`

#### Scenario: идемпотентный повтор после неудачного push
- WHEN коммит доставки уже создан, push сорвался, и в дереве есть backlog
  `tasks/<O>/`
- THEN повторный `owl commit-push <T>` идёт по retry-ветке (только pull+push),
  без повторного stage/flip/commit

# Edge cases

- **Что исключаем.** Только каталоги активных задач `tasks/<id>/` с `id != task_id`.
  Текущую задачу (`tasks/<task_id>/`, если ещё не заархивирована) и `tasks/archive/`
  (куда уехала текущая) — НЕ исключаем. `tasks/index.yaml` стейджим (часть доставки).
- **Источник списка активных.** Активные задачи берём через слой задач
  (`Owl::Tasks::Api`/индекс), не прямым FS-доступом (Constitution no_direct_fs).
- **Нет backlog → поведение неизменно.** Пустой exclude → staging эквивалентен
  прежнему `git add -A` (back-compat); существующие тесты/коммиты не меняются.
- **Известное ограничение.** Исключаются только КАТАЛОГИ задач. Если у другой
  активной задачи есть незакоммиченные изменения кода ВНЕ `tasks/` — они всё ещё
  попадут (определить их принадлежность к задаче нельзя). Документировать в CHANGELOG
  как known limitation; главная боль (артефакты backlog-задач) устранена.
- **Guard/retry в терминах индекса.** Переопределить «пустая доставка» и
  «нечего стейджить» через состояние индекса (`git diff --cached`), а не «весь tree
  чист» — иначе неотслеженный backlog ломает оба инварианта.
- **Версионирование.** Изменение поведения staging → minor bump VERSION + CHANGELOG.

# Acceptance criteria

- [ ] `owl commit-push` стейджит scoped: исключает `tasks/<other-active-id>/`,
  включает доставку текущей задачи (код/docs/архив/индекс/version/CHANGELOG).
- [ ] Список исключений берётся через `Owl::Tasks::Api` (активные минус текущая),
  без прямого FS-доступа из commit_push-слоя.
- [ ] `nothing_to_commit` срабатывает по пустому индексу после scoped-staging даже
  при backlog в дереве.
- [ ] Идемпотентный retry (push-fail → повтор только pull+push) работает при backlog.
- [ ] Нет backlog → поведение и существующие тесты неизменны (back-compat).
- [ ] Регрессионные RSpec: scoped-exclude; nothing_to_commit при backlog; retry при
  backlog; обновлённые тесты транзакции. rspec зелёный; 100% покрытие тронутых
  `**/api.rb`; RuboCop net-zero; minor bump + CHANGELOG (с known limitation).
