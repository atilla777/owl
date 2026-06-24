---
status: approved
summary: "Дать child create тело brief через --brief-body (stdin), сняв нужду писать scratch в tasks/<PARENT>/.briefs/; зафиксировать в skill/overlay-доках дисциплину parallel-команд, cleanup review-running и запрет пересекающихся scope в decompose."
---

# Problem

Полевой отчёт `re` выявил группу проблем вокруг decompose/исполнения, не закрытых
предыдущими задачами:

1. **Scratch-файлы child-brief противоречат правилам.** Decompose-контекст велит
   писать тела child-brief в `tasks/<PARENT>/.briefs/*.md`, тогда как общее правило
   Owl — не читать/редактировать `tasks/` напрямую, кроме resolved artifact path. Нет
   CLI-потока, чтобы передать тело child-brief, поэтому агент нарушает инвариант.
2. **Parallel зависимых owl-команд.** Агент параллельно запускал `step start` и `step
   show`, ловя гонку (show возвращал старый `pending`). Skill-правила явно не
   запрещают parallel для зависимых пар.
3. **Review с changes_required оставляет шаг running.** Субагент корректно не
   завершает review, но шаг остаётся `running`; нужен ручной `owl step reset … review`.
   Это не описано в orchestrator/review overlay.
4. **Decompose не предотвращает пересекающиеся scope рано.** Overlap детей ловится
   только на review, хотя decompose overlay должен требовать непересекающиеся scope
   заранее.

# Goal

Закрыть FF5 (CLI-поток для тела child-brief) и FF6 (зафиксировать в skill/overlay-доках
дисциплину parallel-команд, cleanup review-running и запрет пересекающихся scope),
устранив необходимость прямой записи в `tasks/` и повторяющиеся полевые грабли.

# Scenarios

### Requirement: Тело child-brief передаётся через CLI без записи в tasks/

#### Scenario: child create принимает тело brief из stdin
- WHEN пользователь выполняет `owl task child create --parent P --workflow feature
  --title T --brief-body -` и подаёт markdown тела brief на stdin
- THEN child-задача создаётся с записанным brief-артефактом по resolved-пути, и агенту
  НЕ нужно писать в `tasks/<PARENT>/.briefs/`

#### Scenario: decompose-доки больше не требуют scratch в tasks/
- WHEN агент следует обновлённому decompose-контексту
- THEN он использует `--brief-body` (или resolved artifact path), а инструкция писать
  в `tasks/<PARENT>/.briefs/` удалена/заменена

### Requirement: Skill-доки фиксируют дисциплину parallel-команд

#### Scenario: зависимые owl-команды не запускаются параллельно
- WHEN агент собирается выполнить `step start` затем `step show` (или иную зависимую
  пару, мутатор→читатель)
- THEN правила skill (`_owl_conventions` / owl-step-execution) явно требуют
  последовательного выполнения, чтобы избежать гонки stale-read

### Requirement: changes_required корректно разблокирует шаг review

#### Scenario: после changes_required шаг review приводится в нужный статус
- WHEN review-шаг завершается вердиктом `changes_required` и остаётся `running`
- THEN orchestrator/review overlay явно описывает шаг привести review в pending
  (`owl step reset … review`) перед повторной правкой/прогоном

### Requirement: decompose требует непересекающиеся scope детей

#### Scenario: пересекающиеся scope отклоняются на этапе decompose
- WHEN агент формирует детей с пересекающимися файловыми scope
- THEN decompose-контекст требует развести scope ДО review (явная инструкция/чеклист),
  а не полагаться на отлов на review

# Edge cases

- **Совместимость child create.** `--brief-body` — опциональный флаг; существующее
  поведение `--brief`/без brief не меняется. Взаимоисключение `--brief` и
  `--brief-body` определить явно (или приоритет).
- **Stdin `-`.** Соглашение `-` = читать stdin, консистентно с прочими `--body -`
  командами Owl (workflow/artifact-type).
- **Валидация.** Переданное тело brief проходит обычную валидацию артефакта; невалидное
  — понятная ошибка, не молчаливое создание.
- **Доки vs код.** FF6 — преимущественно изменения `skills/**` и
  `workflows/**/decompose.context.md` (+ синхро `.owl/` копии); это
  consumer-materialized → требует bump `Owl::VERSION` + CHANGELOG и (для skills)
  последующего `owl upgrade` для `.claude/`.
- **Версионирование.** Bump `Owl::VERSION` (minor — новый CLI-флаг + изменённые seed
  skill/overlay-доки) + `CHANGELOG.md`.

# Acceptance criteria

- [ ] `owl task child create … --brief-body -` создаёт child с brief-артефактом из
  stdin по resolved-пути; без прямой записи в `tasks/<PARENT>/.briefs/`.
- [ ] Decompose-контекст (`workflows/composite_feature/decompose.context.md` + `.owl/`
  копия) обновлён: использовать `--brief-body`, требовать непересекающиеся scope детей
  до review; ссылка на `.briefs/` удалена/заменена.
- [ ] `skills/_owl_conventions.md` / `skills/owl-step-execution` фиксируют запрет
  parallel для зависимых owl-команд (мутатор→читатель, напр. `step start`→`step show`).
- [ ] `skills/owl-orchestrator` / review overlay описывают cleanup шага при
  `changes_required` (`owl step reset … review`).
- [ ] Тесты на `--brief-body` (создание + валидация + взаимоисключение с `--brief`).
- [ ] `bundle exec rspec` зелёный; 100% покрытие затронутых `lib/owl/**/api.rb`;
  RuboCop net-zero на трогаемых файлах.
- [ ] `Owl::VERSION` поднят + запись в `CHANGELOG.md`.

# Out of scope

- Безопасный scoped-staging `owl commit-push` (отдельная находка — backlog).
- Автоматический reset review при changes_required в коде (здесь — документная
  фиксация; авто-reset можно вынести в отдельную задачу).
