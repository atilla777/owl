---
status: approved
summary: "Привести merge_docs/publish в соответствие с реальностью: честная проза (без overselling «merge/база знаний»), реализовать задокументированный, но отсутствующий flip design approved→shipped, добавить лёгкий генерируемый docs/README.md-индекс опубликованных доков. Без полноценного KB (его роль несут spec-слой и TASK-0015); step-id merge_docs не переименовываем (breaking, дорого)."
---

# Brief: merge_docs/publish — честность + лёгкий индекс + fix shipped-flip

## Problem

Шаг workflow называется `merge_docs`, команда — `owl publish`, а проза в
контексте шага и доках обещает «merge published docs» / «source of truth for
domain knowledge». На деле (карта кода):

- `owl publish` для feature просто **копирует один файл** `tasks/<ID>/design.md`
  → `docs/<ID>/design.md` по `publishes:`-правилу (`lib/owl/publish/...`); плюс
  `owl spec merge` применяет опциональный `spec_delta` (пока ни одной задачей не
  используется).
- В `docs/` лежат разрозненные per-task копии `design.md` (сейчас 3 шт.) — **без
  индекса, перелинковки и поиска**. «Базы знаний» нет; имя `merge_docs` и проза
  про «merge/knowledge» завышают реальность.
- Контекст шага `merge_docs.context.md` обещает, что при публикации статус
  `design` меняется `approved → shipped`, но **код этого не делает**
  (`Publisher` копирует файл as-is) — реальное расхождение «доки vs код».

Это противоречит общему вектору проекта на правдивость сигналов (objective
verification gate, honest self-report).

## Goal

1. **Честность.** Переписать прозу шага и команды (контекст
   `merge_docs.context.md` во всех вариантах, скиллы, релевантные доки) так,
   чтобы она описывала реальное поведение — «публикует артефакты задачи в
   `docs/` по `publishes:`-правилам и применяет опциональный `spec_delta`», без
   формулировок «merge»/«база знаний».
2. **Fix shipped-flip.** Реализовать задокументированный переход: после успешной
   (не dry-run) публикации статус `design` становится `shipped` (и в каноничном
   артефакте задачи, и в опубликованной копии).
3. **Лёгкий индекс.** При публикации поддерживать генерируемый `docs/README.md`
   — список опубликованных доков со ссылками (findability без поиска/KB).
4. **Границы.** НЕ строить полноценную базу знаний (агрегация/поиск/`owl docs`):
   эту роль несут `specs/<domain>/spec.md` (живая спека) и TASK-0015
   (кросс-задачная память). НЕ переименовывать step-id `merge_docs` (breaking:
   формат on-disk workflow, step-id в архивных задачах, JSON-контракт).

Решения, принятые на брифе (вход для design):
- Направление — «честно упростить», а не полноценный KB.
- Имя step-id `merge_docs` сохраняем; честность достигается прозой + bugfix +
  лёгким индексом, а не массовым breaking-ренеймом.
- shipped-flip — реализуем (это баг, не выкидываем обещание).

## Scenarios

### Requirement: Publish flips the design status to shipped

The system SHALL set the `design` artifact's front-matter status to `shipped` after a successful non-dry-run publish.

#### Scenario: Approved design becomes shipped on publish
- WHEN `owl publish TASK-ID` выполняется (не dry-run) для задачи с опубликованным `design` в статусе `approved`
- THEN после команды статус `design` равен `shipped`
- AND опубликованная копия в `docs/<ID>/design.md` также имеет `status: shipped`
- TEST: spec/owl/publish/api_spec.rb

#### Scenario: Dry-run does not flip status
- WHEN `owl publish TASK-ID --dry-run` выполняется для `approved` design
- THEN ни статус артефакта, ни файлы не меняются (статус остаётся `approved`)
- TEST: spec/owl/publish/api_spec.rb

#### Scenario: Re-publish is idempotent
- WHEN `owl publish` выполняется повторно для уже `shipped` design
- THEN команда завершается `ok` без ошибки и статус остаётся `shipped`
- TEST: spec/owl/publish/api_spec.rb

### Requirement: Publish maintains a generated docs index

The system SHALL maintain a generated `docs/README.md` listing the published task docs with links after a non-dry-run publish.

#### Scenario: Index lists published docs
- WHEN `owl publish TASK-ID` опубликовал `docs/<ID>/design.md`
- THEN `docs/README.md` существует и содержит ссылку на `docs/<ID>/design.md`
- AND индекс перечисляет ранее опубликованные доки, а не только текущую задачу
- TEST: spec/owl/publish/docs_index_spec.rb

#### Scenario: Index generation is deterministic and dry-run-safe
- WHEN `owl publish --dry-run` выполняется
- THEN `docs/README.md` не перезаписывается
- AND повторный реальный publish даёт стабильный (идемпотентный) индекс при том же наборе доков
- TEST: spec/owl/publish/docs_index_spec.rb

### Requirement: Step and command prose match real behavior

The system SHALL describe the publish step and command by what they actually do, without claiming "merge" or "knowledge base" semantics they do not implement.

#### Scenario: Context drops overselling language
- WHEN читатель открывает `merge_docs.context.md` (и материализованные копии) и прозу про publish в скиллах/доках
- THEN формулировки описывают «публикацию артефактов в `docs/` + опциональный `spec_delta`», без «merge published docs»/«база знаний»
- AND описан реально реализованный flip `approved→shipped` и генерируемый индекс
- TEST: spec/owl/docs/merge_docs_prose_spec.rb

### Requirement: Spec-less and source-less publishes stay graceful

The system SHALL keep existing no-op behavior for tasks without a publishable source or without a spec_delta.

#### Scenario: No regression for graceful no-ops
- WHEN публикуется задача без `spec_delta` и/или с optional-источником, которого нет
- THEN `owl spec merge` возвращает `no_spec_delta`, а publish — `skipped_missing_source` для optional-правила, шаг завершается успешно
- AND индекс и flip не падают при отсутствии источника
- TEST: spec/owl/integration/merge_docs_spec_merge_spec.rb

## Edge cases

- **Идемпотентность flip**: повторный publish на `shipped` не ошибается; flip
  применяется только при наличии источника `design`.
- **dry-run**: ни flip, ни индекс, ни копии не пишутся.
- **Отсутствует `design`** (optional source missing): flip пропускается, индекс
  строится по фактически существующим докам, шаг не падает.
- **Бэкапы**: при перезаписи `docs/<ID>/design.md` и `docs/README.md` сохранять
  существующее поведение `.bak-<timestamp>` (или явно обосновать отказ для
  генерируемого индекса).
- **Согласованность source/published**: статус `shipped` должен совпадать в
  каноничном артефакте задачи и в опубликованной копии (порядок flip→copy решает
  design).
- **Back-compat контракта publish**: результат `owl publish --json` может
  получить доп. сведения (индекс/flip), но существующие ключи (`results`,
  `action`) не ломаются → bump **minor**.
- **Несколько `publishes:`-правил/композит**: индекс агрегирует все
  опубликованные доки независимо от их числа.

## Acceptance criteria

- `owl publish` (не dry-run) переводит `design` в `shipped` (источник + копия);
  dry-run ничего не меняет; повтор идемпотентен.
- Поддерживается генерируемый `docs/README.md` со ссылками на опубликованные
  доки; dry-run его не трогает; генерация детерминирована/идемпотентна.
- Проза `merge_docs.context.md` (все варианты), скиллов и затронутых доков
  приведена к реальности (без «merge»/«knowledge base»); описывает flip и индекс.
- Сохранены graceful no-ops (`no_spec_delta`, `skipped_missing_source`); нет
  регрессий full-cycle.
- step-id `merge_docs` НЕ переименован; полноценный KB НЕ строится.
- Соблюдены правила проекта: bump `Owl::VERSION` (minor) + `CHANGELOG.md`
  (затронуты `lib/**`, `workflows/**`, `skills/**`); 100% покрытие строк для
  изменённых `lib/owl/**/api.rb` (в т.ч. `lib/owl/publish/api.rb`); доступ к
  `docs/`/`tasks/` только через слои Owl/Storage; конституция соблюдена.
- Тесты покрывают: flip (apply/dry-run/idempotent/no-source), индекс
  (содержимое/dry-run/детерминизм), прозу, отсутствие регрессий no-op.
