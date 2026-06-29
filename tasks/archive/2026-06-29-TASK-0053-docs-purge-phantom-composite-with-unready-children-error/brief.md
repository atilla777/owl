---
status: approved
summary: >-
  Вычистить фантомный код ошибки composite_with_unready_children из source-контента
  Owl (owl-orchestrator SKILL.md, archive.context.md ×3, README.md): такого кода в
  lib/ нет. Реальные сущности — ошибка архивации workflow_incomplete и статус
  blocked_by_children. Заменить ссылки на корректные коды/статусы.
---

# Problem

В агент-facing документации Owl фигурирует структурный код ошибки
`composite_with_unready_children`, которого **не существует** в кодовой базе:
`grep -rn composite_with_unready_children lib/ bin/` пуст. Реальные сущности:

- Ошибка completion-gate архивации — `:workflow_incomplete`
  (`lib/owl/tasks/internal/archive/completion_gate.rb:48`); прочие коды архивации:
  `publish_required`, `already_archived`, `task_workflow_missing`,
  `workflow_source_missing`, `slug_collision_limit`. Кода `composite_with_unready_children`
  среди них нет.
- Ожидание parent'ом детей выражается **статусом** `blocked_by_children`
  (readiness-движок прячет gated-шаги `archive`/`commit_push` из `ready-steps`),
  а `owl next` возвращает `action.kind: handoff_composite`.

Фантомный код встречается в source-контенте (который материализуется в
consumer-проекты):

- `skills/owl-orchestrator/SKILL.md` — 3 вхождения (Stop Conditions ×2 + Notes).
- `workflows/feature/archive.context.md`, `workflows/hotfix/archive.context.md`,
  `workflows/refactor/archive.context.md` — по 1 вхождению.
- `README.md` — 1 вхождение.

Из-за этого оркестратор-агент инструктируется ловить несуществующий код и может
неверно трактовать реальную ошибку `workflow_incomplete` / статус
`blocked_by_children` при архивации composite-родителя.

# Goal

Привести агент-facing документацию в соответствие с реальным CLI-контрактом:
убрать все ссылки на фантомный `composite_with_unready_children` из source-контента
и заменить их корректной формулировкой (реальная ошибка `workflow_incomplete` для
преждевременной архивации + статус `blocked_by_children` / `handoff_composite` для
ожидания детей), не меняя смысла остальной инструкции.

# Scenarios

### Requirement: source-контент не упоминает фантомный код

The system SHALL NOT reference the non-existent error code
`composite_with_unready_children` in any Owl source documentation
(`skills/**`, `workflows/**`, `README.md`).

#### Scenario: grep по source-контенту пуст
- WHEN после правки выполняется
  `grep -rn composite_with_unready_children skills/ workflows/ README.md`
- THEN совпадений нет (0 строк)
- AND `CHANGELOG.md` (исторические записи) при этом НЕ редактируется

### Requirement: замена ссылается на реальные коды/статусы

The system SHALL replace each removed reference with language describing the real
archive-gate error `workflow_incomplete` and/or the `blocked_by_children` status
(and `owl next` `handoff_composite`), matching the actual CLI behaviour.

#### Scenario: owl-orchestrator SKILL.md описывает реальное поведение
- WHEN читается обновлённый `skills/owl-orchestrator/SKILL.md` (Stop Conditions и Notes)
- THEN преждевременная `owl archive PARENT` описана как возвращающая
  `workflow_incomplete` (а не фантомный код)
- AND ожидание детей описано через статус `blocked_by_children` /
  `handoff_composite`, как и в остальном тексте skill'а

#### Scenario: archive.context.md ×3 и README описывают реальный код
- WHEN читаются обновлённые `workflows/{feature,hotfix,refactor}/archive.context.md`
  и `README.md`
- THEN ссылка на `composite_with_unready_children` заменена на корректную
  (`workflow_incomplete` для неполной архивации), смысл абзаца сохранён

### Requirement: материализованные копии пересобираются, а не правятся вручную

The system SHALL refresh the materialised copies under `.claude/` and `.owl/`
through `bin/owl upgrade --force` rather than hand-editing them.

#### Scenario: .claude/.owl синхронизированы из source
- WHEN после правки source-контента выполняется `bin/owl upgrade` (или
  `init --force`) и затем grep по `.claude/skills/` и `.owl/workflows/`
- THEN фантомный код отсутствует и там (копии пересобраны из обновлённого source)

# Edge cases

- **CHANGELOG.md / tasks/**.** Историческая запись в `CHANGELOG.md` и заголовок
  этой задачи в `tasks/index.yaml` НЕ являются ложными ссылками на контракт —
  их не трогаем (CHANGELOG — это летопись; редактировать прошлые записи нельзя).
- **Точность замены.** Нужно убедиться, что `owl archive` для неполного
  composite-родителя действительно отдаёт `workflow_incomplete` (gated-шаги
  `archive`/`commit_push` не `done`), а не какой-то другой код — сверить с
  `completion_gate.rb` при реализации, чтобы замена не ввела новую неточность.
- **Версионирование.** Правка задевает `skills/**` и `workflows/**`
  (consumer-материализуемый seed-контент) и `README.md` — по Конституции §7.1
  это требует bump `Owl::VERSION` + запись в `CHANGELOG.md` (patch: back-compat
  правка документации). Чистый `docs/**` был бы вне bump, но skills/workflows — нет.
- **Материализованные артефакты.** `.claude/skills/owl-orchestrator/SKILL.md` и
  `.owl/workflows/*/archive.context.md` — генерируемые копии; правим source и
  пересобираем через `owl upgrade --force`, не редактируем напрямую.
- **Смысловая нейтральность.** Замена не должна менять инструкцию по существу —
  только заменить неверное имя кода на верное и согласовать формулировку.

# Acceptance criteria

- `grep -rn composite_with_unready_children skills/ workflows/ README.md` → 0 совпадений.
- Каждое удалённое вхождение заменено корректной формулировкой про
  `workflow_incomplete` и/или статус `blocked_by_children` / `handoff_composite`;
  смысл абзацев сохранён.
- `CHANGELOG.md` исторические записи не изменены (кроме новой записи о версии).
- `.claude/skills/` и `.owl/workflows/` пересобраны через `bin/owl upgrade --force`
  и тоже не содержат фантомного кода.
- `Owl::VERSION` поднят (patch) + новая запись в `CHANGELOG.md` в том же коммите.
- `bundle exec rspec` остаётся зелёным (правка только документации; кода lib/ не касается).
