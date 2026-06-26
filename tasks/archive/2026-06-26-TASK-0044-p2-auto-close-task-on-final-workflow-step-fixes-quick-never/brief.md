---
status: approved
summary: >-
  Авто-закрытие задачи при завершении терминального шага workflow без archive:
  обобщить ArchiveFinalizer в TaskFinalizer, выставлять status=done и сбрасывать
  current-указатель, чтобы quick-задачи не залипали в open/available.
---

# Problem

`owl step complete` выставляет терминальный статус только **шагу**
(`status: done`), но никогда не трогает статус **задачи**. Терминальный статус
задаче (`archived`) сегодня ставит исключительно шаг `archive` через команду
`owl archive`. `ArchiveFinalizer` (`lib/owl/steps/internal/archive_finalizer.rb`)
сбрасывает current-указатель только при `status == 'archived'`.

Из-за этого workflow **без шага `archive`** никогда не переходит в терминальный
статус. Единственный такой сидовый workflow сейчас — `quick`
(`brief → implement → commit_push`, без design/plan/review/archive). Последствия:

- **quick-never-terminal.** После завершения `commit_push` (терминальный шаг)
  задача остаётся `status: open` навсегда — нет механизма перевести её в
  терминальный статус.
- **done-but-open lingering.** Фильтры `owl task available` / `owl task ready`
  (`availability_scanner.rb`, `ready_scanner.rb`) исключают только терминальные
  статусы (`archived`/`abandoned`/`done`). Полностью завершённая quick-задача с
  `status: open` продолжает появляться в available/ready и повторно
  авто-выбираться оркестратором (`owl next` → `done`, цикл вхолостую).
- **current-указатель не освобождается.** `ArchiveFinalizer` — no-op для
  не-archived задач, поэтому `owl task current` продолжает указывать на
  завершённую quick-задачу до ручного переключения.

Workflow с шагом `archive` (`feature`, `hotfix`, `refactor`,
`composite_feature`) не затронуты: они переходят в `archived` (терминальный) на
шаге `archive` до `commit_push`, и `ArchiveFinalizer` уже освобождает их
указатель.

# Goal

Обобщить финализацию задачи так, чтобы завершение **терминального шага** любого
workflow (того, что никто не `requires`; при этом все шаги задачи в
`done`/`skipped`) при **не**терминальном статусе задачи переводило задачу в
терминальный статус `done` и освобождало current-указатель — переиспользуя
существующую логику `ArchiveFinalizer`/`CurrentResetter`. Поведение
archive-содержащих workflow при этом не меняется.

# Scenarios

### Requirement: авто-закрытие в done на терминальном шаге

The system SHALL set a task's status to `done` when `owl step complete`
finishes the workflow's terminal step, all of the task's steps are
`done`/`skipped`, and the task's status is not already terminal.

#### Scenario: quick-задача завершает commit_push
- WHEN `owl step complete TASK-ID commit_push` завершает терминальный шаг
  quick-задачи (статус задачи `open`, все шаги `done`/`skipped`)
- THEN статус задачи становится `done`
- AND задача исчезает из `owl task available` и `owl task ready`

#### Scenario: завершение нетерминального шага не закрывает задачу
- WHEN `owl step complete` завершает шаг, у которого есть зависящие
  (downstream) шаги, ещё не выполненные
- THEN статус задачи остаётся прежним (не `done`)

### Requirement: освобождение current-указателя при авто-закрытии

The system SHALL release the current-task pointer when a task is auto-closed
to `done`, identically to the archived-task path.

#### Scenario: указатель сброшен после авто-close
- WHEN quick-задача авто-закрывается в `done` на шаге `commit_push`, и
  current-указатель указывал на неё
- THEN current-указатель сбрасывается (CurrentResetter)
- AND `owl task current` больше не возвращает эту задачу

### Requirement: неизменность archive-содержащих workflow

The system SHALL NOT change the terminal status or pointer behaviour of
workflows that already terminate via an `archive` step.

#### Scenario: feature-задача проходит archive → commit_push как раньше
- WHEN feature-задача проходит шаг `archive` (статус → `archived`), а затем
  завершает терминальный шаг `commit_push`
- THEN статус остаётся `archived` (не перезаписывается в `done`)
- AND current-указатель освобождается ровно как сейчас (через ту же
  обобщённую финализацию)

# Edge cases

- **Идемпотентность.** Повторный `owl step complete` на уже завершённой задаче
  (`done`) не должен падать и не должен менять терминальный статус — `done`
  остаётся `done`.
- **Уже терминальный статус.** Если задача уже `archived`/`abandoned`/`done`,
  авто-close не перезаписывает её на `done` (только не-терминальный →
  `done`).
- **Не все шаги терминальны.** Если терминальный шаг как-то завершился, но
  остались `pending`/`running`/`blocked` шаги, авто-close не срабатывает
  (условие «все шаги done/skipped», как в `ArchiveFinalizer.all_steps_terminal?`).
- **Несколько листьев графа.** Если у workflow несколько терминальных шагов
  (нет единственного «последнего»), критерий — «все шаги done/skipped», а не
  «завершён конкретный id»; финализация срабатывает на завершении любого шага,
  после которого все шаги стали терминальными.
- **Skipped-шаги (`when:` предикат ложен).** Пропущенные шаги считаются
  терминальными (`skipped`) и не препятствуют авто-close — согласовано с
  TASK-0037 (conditional-skip учитывается в доступности).
- **Composite-родитель.** Авто-close не должен конфликтовать с гейтом
  `children_complete`: для composite терминальные шаги (`archive`/`commit_push`)
  держатся до готовности детей; общий критерий «все шаги done/skipped» это
  уже учитывает (гейтнутые шаги не завершены, пока дети не готовы).

# Acceptance criteria

- [ ] Завершение терминального шага quick-задачи (`commit_push`) переводит
      задачу в `status: done` и убирает её из `owl task available`/`ready`.
- [ ] current-указатель освобождается при авто-close (через `CurrentResetter`),
      `owl task current` больше не возвращает завершённую задачу.
- [ ] Логика `ArchiveFinalizer` обобщена (напр. в `TaskFinalizer`) без
      изменения поведения archive-содержащих workflow: feature/hotfix/refactor/
      composite по-прежнему остаются `archived` после `archive`, статус не
      перезаписывается в `done`.
- [ ] Авто-close не срабатывает, пока остались незавершённые
      (`pending`/`running`/`blocked`) шаги или статус задачи уже терминальный;
      повторный `owl step complete` идемпотентен.
- [ ] Покрыто спеками: `owl step complete` на терминальном шаге (quick →
      `done` + сброс указателя), отсутствие регрессии для archive-пути,
      идемпотентность, не-все-шаги-терминальны. Если затрагивается публичный
      `lib/owl/**/api.rb` — 100% покрытие новых строк.
- [ ] `Owl::VERSION` поднят (patch — фикс/обратносовместимое поведение) и
      добавлена запись в `CHANGELOG.md` в том же коммите (изменение в
      `lib/**/*.rb`).
- [ ] Изменение не нарушает FS-layering (доступ к `tasks/` только через Backend,
      без прямого FS из Internal/Api) и Конституцию проекта.
