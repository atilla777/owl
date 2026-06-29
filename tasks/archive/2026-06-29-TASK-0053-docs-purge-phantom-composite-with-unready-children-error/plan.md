# Goal

Удалить все 6 вхождений фантомного кода `composite_with_unready_children` из
source-контента Owl и заменить их корректной формулировкой (реальная ошибка
архивации `workflow_incomplete` + статус `blocked_by_children` / `handoff_composite`),
сохранив смысл абзацев. Пересобрать материализованные копии через
`owl upgrade --force`, поднять `Owl::VERSION` (patch) и добавить запись в `CHANGELOG.md`.

# Checklist

- [ ] `skills/owl-orchestrator/SKILL.md` (3 вхождения):
  - Stop Conditions, абзац про `blocked_by_children`: заменить хвост
    «…or `owl archive PARENT-ID` returns `composite_with_unready_children` after
    you believed all children were done» → на реальную ошибку
    `workflow_incomplete` (gated `archive`/`commit_push` ещё не `done`).
  - Stop Conditions, перечень кодов «(`task_workflow_missing`, `unknown_step_id`,
    `step_not_ready`, `composite_with_unready_children`, etc.)» → убрать фантом,
    заменить на реальный код (например `workflow_incomplete` или `publish_required`).
  - Notes, абзац про composite-архивацию: «…if any child is unready, it returns
    `composite_with_unready_children` rather than partial archive» → описать через
    реальное поведение: gated-шаги держатся как `blocked_by_children`, а
    преждевременный `owl archive` отдаёт `workflow_incomplete` (не частичную архивацию).
- [ ] `workflows/feature/archive.context.md` (1 вхождение, секция `## Mode`):
  «if any child is not ready, the command returns `composite_with_unready_children`
  and lists the missing steps» → заменить на корректный код `workflow_incomplete`
  (с `details.incomplete_steps`), смысл «не частичная архивация» сохранить.
- [ ] `workflows/hotfix/archive.context.md` — то же вхождение, та же замена.
- [ ] `workflows/refactor/archive.context.md` — то же вхождение, та же замена.
- [ ] `README.md` (1 вхождение, ~строка 659): «When `owl archive PARENT-ID` returns
  `composite_with_unready_children`, do not "force" anything» → заменить код на
  `workflow_incomplete`, сохранить мысль «не форсить, показать незавершённые шаги».
- [ ] `lib/owl/version.rb` — поднять `Owl::VERSION` `1.4.0` → `1.4.1` (patch:
  back-compat правка консумер-материализуемой документации).
- [ ] `CHANGELOG.md` — запись `[1.4.1]`: purge фантомного кода
  `composite_with_unready_children` из orchestrator-skill / archive-context / README;
  корректные коды — `workflow_incomplete` + статус `blocked_by_children`.
  (Существующие исторические записи НЕ менять.)
- [ ] `bin/owl upgrade --force` — пересобрать материализованные копии
  `.claude/skills/owl-orchestrator/SKILL.md` и `.owl/workflows/*/archive.context.md`
  из обновлённого source.

# Smoke test

```
grep -rn composite_with_unready_children skills/ workflows/ README.md   # → 0
grep -rn composite_with_unready_children .claude/ .owl/                 # → 0 после upgrade --force
bin/owl --version          # → 1.4.1
bundle exec rspec          # зелёный (правка только документации)
```

# Scope

`skills/owl-orchestrator/SKILL.md`, `workflows/{feature,hotfix,refactor}/archive.context.md`,
`README.md`, `lib/owl/version.rb`, `CHANGELOG.md`, плюс пересборка `.claude/`+`.owl/`
через `owl upgrade --force`. Кода `lib/` (кроме version.rb) не касаемся.

# Constraints

- Замена нейтральна по смыслу: меняем только неверное имя кода на верное и
  согласуем формулировку; инструкцию по существу не переписываем.
- `CHANGELOG.md` исторические записи неприкосновенны; добавляем только новую `[1.4.1]`.
- Материализованные копии (`.claude/`, `.owl/`) НЕ редактируем вручную — только
  через `owl upgrade --force` из обновлённого source.
- Реальный код архивации сверить с `lib/owl/tasks/internal/archive/completion_gate.rb`
  (`:workflow_incomplete`), чтобы замена не ввела новую неточность.
- Bump `Owl::VERSION` + `CHANGELOG.md` в том же коммите (Constitution §7.1) — правка
  задевает `skills/**`, `workflows/**`, `README.md` (в scope для bump).

# Files to inspect

- `lib/owl/tasks/internal/archive/completion_gate.rb` — реальный код
  `:workflow_incomplete` + `details.incomplete_steps` (источник истины для замены).
- `lib/owl/orchestration/internal/next_action_resolver.rb`,
  `lib/owl/status/internal/constants.rb` — реальный статус `blocked_by_children` /
  `handoff_composite` (для согласованной формулировки).
- `skills/owl-orchestrator/SKILL.md` — строки ~85, ~87, ~94 (3 вхождения).
- `workflows/{feature,hotfix,refactor}/archive.context.md` — секция `## Mode`.
- `README.md` — ~строка 659.

# Tests and verification

- Grep-проверки из Smoke test: 0 совпадений в source и (после upgrade) в `.claude/`/`.owl/`.
- `bundle exec rspec` зелёный (известный wart: красный exit при 0 failures — судить
  по количеству failures, не по exit-коду).
- Визуально подтвердить, что каждая замена сохранила смысл абзаца и ссылается на
  существующий код/статус.

# Out of scope

- Любые изменения поведения CLI/кода архивации (`lib/owl/**` кроме `version.rb`).
- Введение нового кода ошибки или переименование `workflow_incomplete`/`blocked_by_children`.
- Редактирование исторических записей `CHANGELOG.md` или заголовков в `tasks/index.yaml`.
- Правка `kos-*` legacy-снимка и прочей документации, не содержащей фантомного кода.
