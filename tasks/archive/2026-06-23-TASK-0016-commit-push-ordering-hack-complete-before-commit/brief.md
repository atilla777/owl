---
status: approved
summary: >-
  Убрать ordering-hack «complete-before-commit» из терминального шага
  commit_push, введя атомарную CLI-команду `owl commit-push TASK-ID`. Команда
  инкапсулирует stage → запись commit_push=done → re-stage → git lock → commit
  → pull --rebase → push → unlock в одну операцию, так что флаг `done` попадает
  в тот же коммит без двойного staging и без отдельного sync-коммита. При сбое
  ДО коммита — откат (step остаётся running, коммита нет); при успешном commit,
  но провале push — локальный коммит сохраняется, команда идемпотентно
  до-пушивается (ретрай push), без дублей и без состояния «done, но не
  запушено». Объём — только commit_push.
---

# Brief — Транзакционность commit_push: убрать ordering-hack complete-before-commit

## Problem

Текущий шаг `commit_push` (терминальный для `feature`/`composite_feature`/
`refactor`) выполняется по **инвертированному** порядку относительно обычного
execution-шага. По `commit_push.context.md` и оверлею `.owl/overlays/commit_push.md`
скилл обязан:

1. `git add -A` (в этот момент архивный `task.yaml` всё ещё `commit_push: running`);
2. `owl step complete` — флипнуть шаг в `done` в архивном `task.yaml`;
3. `git add -A` **ещё раз** — чтобы флип `done` попал в коммит;
4. `owl git lock` → `git commit` → `git pull --rebase` → `git push` → `owl git unlock`.

Это «ordering-hack»: завершение записывается ДО коммита, с двойным staging,
чтобы `commit_push: done` оказался в том же коммите. Проблемы:

- **Хрупкость порядка.** Если агент следует обычному порядку execution-шага
  (сделать работу → `complete`), архивный `task.yaml` остаётся «грязным» после
  коммита и требует отдельного **sync-коммита** «sync commit_push step state to
  done» (это реально происходит — см. историю git: TASK-0014, TASK-0018).
- **Несогласованное состояние.** Если `owl step complete` уже флипнул `done`, а
  последующий `commit`/`push` упал — шаг помечен `done`, но ничего не
  закоммичено/не запушено: «done, но не доставлено».
- **Двойной `git add -A`** и ручная оркестрация 7 действий в прозе скилла —
  легко ошибиться, трудно тестировать, дублируется в каждом workflow-оверлее.

Нет единой атомарной операции, которая гарантировала бы: либо доставка
(коммит с `done` внутри + push) состоялась целиком, либо состояние осталось
консистентным для ретрая.

## Goal

Ввести атомарную CLI-команду **`owl commit-push TASK-ID`**, инкапсулирующую всю
последовательность commit_push в одну транзакционную операцию, и переключить
скилл/оверлей commit_push на её вызов вместо ручной 7-шаговой прозы.

Конкретно:

1. `owl commit-push TASK-ID [--json]` выполняет: `git add -A` → запись
   `commit_push: done` в `task.yaml` → `git add -A` (флип в индекс) → взять
   push-lock (`Owl::Locks`/`owl git lock`) → `git commit` → `git pull --rebase`
   → `git push` → отпустить lock — как одну команду.
2. Флаг `commit_push: done` попадает в **тот же** коммит (никакого отдельного
   sync-коммита, никакого «грязного» `task.yaml` после).
3. **Семантика сбоя:**
   - сбой ДО `git commit` (staging/lock/commit) → **откат**: `commit_push`
     возвращается в `running`, коммит не создан, рабочее дерево не «доставлено»;
   - `git commit` успешен, но `git pull --rebase`/`git push` упал → локальный
     коммит (уже содержащий `done`) **сохраняется**; команда **идемпотентна** и
     при повторном запуске дотягивает только pull --rebase + push (ретрай), не
     создавая дублирующий коммит и не оставляя «done, но не запушено» как
     терминальное состояние.
4. Скилл `owl-step-execution`/оверлей `commit_push` упрощаются до вызова
   `owl commit-push` (одна команда) с сохранением существующих предусловий
   (проверка `git status` на посторонние файлы, push к `main` напрямую, один
   коммит на доставку) и stop-conditions.

### Не входит в объём (Non-goals)

- Обобщение транзакционной модели завершения на другие execution-шаги
  (`archive` и пр.) — выбран **точечный** объём только для `commit_push`.
- Изменение политики ветки/remote (push в `main` напрямую остаётся).
- Строгий git-уровневый откат уже созданного коммита при провале push
  (выбрана прагматика «коммит сохраняется, ретрай push»).
- Изменение формата `task.yaml` или контракта других команд.

## Scenarios

### Requirement: атомарная команда commit-push

The system SHALL предоставлять команду `owl commit-push TASK-ID`, которая
выполняет staging, запись `commit_push: done`, commit, pull --rebase и push как
одну операцию.

#### Scenario: успешная доставка одним вызовом
- WHEN рабочее дерево содержит изменения задачи и `commit_push` шаг готов/running
- AND пользователь выполняет `owl commit-push TASK-ID --json`
- THEN создаётся один коммит, содержащий изменения задачи И флаг
  `commit_push: done` в `task.yaml`
- AND коммит запушен в `main`
- AND отдельный sync-коммит «sync ... step state to done» НЕ требуется
- TEST: spec/owl/commit_push/api_spec.rb

#### Scenario: флаг done внутри того же коммита
- WHEN `owl commit-push` создаёт коммит
- THEN в этом коммите `task.yaml` уже имеет `commit_push: done` (рабочее дерево
  чистое после команды — нет «грязного» task.yaml)
- TEST: spec/owl/commit_push/api_spec.rb

### Requirement: откат при сбое до коммита

The system SHALL при сбое любой операции ДО `git commit` оставлять
`commit_push` в статусе `running` и не создавать коммит.

#### Scenario: провал на staging/commit откатывает статус
- WHEN `owl commit-push` падает на этапе до коммита (например, commit невозможен)
- THEN `commit_push` остаётся `running` (флип `done` откатан, если был)
- AND коммит не создан, ошибка возвращается структурно (`ok:false`, `error.code`)
- TEST: spec/owl/commit_push/api_spec.rb

### Requirement: идемпотентный ретрай при провале push

The system SHALL при успешном `git commit`, но провале `pull --rebase`/`push`
сохранять локальный коммит и допускать идемпотентный повторный запуск, который
дотягивает только pull --rebase + push.

#### Scenario: push упал — коммит сохранён, повтор дотягивает
- WHEN `git commit` прошёл, но `git push` упал (например, недоступен remote)
- THEN локальный коммит (с `commit_push: done`) сохранён, не сброшен
- AND повторный `owl commit-push TASK-ID` не создаёт второй коммит, а выполняет
  pull --rebase + push для уже существующего коммита
- AND нет терминального состояния «done, но не запушено»: пока push не прошёл,
  команда сообщает об этом (`ok:false`) и остаётся ретрайбельной
- TEST: spec/owl/commit_push/api_spec.rb

### Requirement: сохранение push-сериализации и предусловий

The system SHALL использовать существующий push-lock (`Owl::Locks`/`owl git
lock`) и сохранять предусловия оверлея commit_push (проверка на посторонние
файлы, push в `main`).

#### Scenario: одновременные сессии не пушат разом
- WHEN две сессии вызывают `owl commit-push` одновременно
- THEN push-lock сериализует их; вторая ждёт/получает `lock_held` и не пушит
  параллельно
- TEST: spec/owl/commit_push/locking_spec.rb

## Edge cases

- **Нечего коммитить** (пустой staging после `git add -A`) → команда не создаёт
  пустой коммит; сообщает понятно (`ok:false`/`nothing_to_commit`) и не флипает
  `done` ложно.
- **commit_push уже `done`** (идемпотентный повтор после успешного commit, но
  до успешного push) → не дублировать коммит; дотянуть push.
- **`git pull --rebase` даёт конфликт** → не пушить, вернуть структурную ошибку
  с требованием человеческого решения (stop-condition оверлея сохраняется).
- **Push-lock занят живой сессией** (`lock_held`) → не `--steal`; вернуть
  ретрайбельную ошибку.
- **Посторонние/подозрительные файлы в `git status`** (секреты, неожиданные
  удаления) → команда/скилл останавливается и не коммитит (предусловие оверлея).
- **Композитный родитель** с gate `children_complete` — вне объёма этой задачи;
  команда оперирует тем шагом/деревом, что ей передали (взаимодействие с
  composite-gate отслеживается отдельно, см. TASK-0019).
- **Откат флипа `done`** при сбое до коммита не должен повредить остальной
  `task.yaml` (точечное изменение статуса шага).

## Acceptance criteria

1. Есть команда `owl commit-push TASK-ID [--json]`, выполняющая stage → запись
   `commit_push: done` → re-stage → lock → commit → pull --rebase → push →
   unlock атомарно; успех даёт один коммит с `done` внутри и push в `main`.
2. Не требуется ни двойной ручной `git add`, ни отдельный sync-коммит; рабочее
   дерево чистое после успешной команды.
3. Сбой ДО коммита → `commit_push` остаётся `running`, коммита нет, ошибка
   структурная.
4. Успешный commit + провал push → локальный коммит сохранён; повтор команды
   идемпотентен (дотягивает push, без второго коммита); нет состояния «done, но
   не запушено» как финального.
5. Push-сериализация через существующий lock сохранена; предусловия и
   stop-conditions оверлея commit_push соблюдены.
6. Скилл `owl-step-execution`/контекст+оверлей `commit_push` обновлены на вызов
   `owl commit-push` вместо 7-шаговой прозы; материализованные копии
   синхронизированы (`owl upgrade`).
7. Публичный API команды покрыт тестами на 100% строк
   (`docs/agents/30_...`); названы spec-файлы (api/locking).
8. Изменение бампит `Owl::VERSION` (новая команда = minor) и добавляет запись в
   `CHANGELOG.md` в том же коммите (Конституция §7.1); JSON-контракт
   `owl commit-push` задокументирован.
9. Edge cases выше либо покрыты поведением, либо явно зафиксированы как
   известные ограничения.
