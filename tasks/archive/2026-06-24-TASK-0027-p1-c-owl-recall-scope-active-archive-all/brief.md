---
status: approved
summary: "owl recall --scope active|archive|all — распространить tf-idf поиск с архива на активные задачи, чтобы находить связанную текущую работу, а не только закрытую."
---

# Problem

`owl recall` ищет похожие задачи tf-idf-методом, но корпус — **только архив**
(`corpus_builder` читает archive role через `Archive::Api`). Активные задачи не
индексируются для поиска. Для трекера это пробел: нельзя найти связанную **текущую**
работу («есть ли уже активная задача про X?»), нет дедупликации новой задачи против
открытых.

# Goal

Дать `owl recall` параметр `--scope active|archive|all`, расширив корпус на активные
задачи (их brief), сохранив текущее поведение по умолчанию (поиск по архиву).

# Scenarios

### Requirement: recall ищет по выбранной области

#### Scenario: поиск по активным задачам
- WHEN пользователь выполняет `owl recall "<query>" --scope active --json`
- THEN ранжирование строится по корпусу активных задач (их brief), и результаты несут
  task_id/title/snippet активных задач

#### Scenario: поиск по всем задачам
- WHEN пользователь выполняет `owl recall "<query>" --scope all --json`
- THEN корпус — активные + архивные задачи; каждый матч помечен областью
  (`scope: active|archived`)

#### Scenario: дефолт сохраняет текущее поведение
- WHEN пользователь выполняет `owl recall "<query>"` без `--scope`
- THEN область по умолчанию `archive` (поведение не меняется для существующих
  вызовов, включая brief-step оркестратора)

# Edge cases

- **Дефолт = archive.** Обратная совместимость: без `--scope` — ровно текущее
  поведение (поиск по архиву). `active`/`all` — opt-in.
- **Источник текста активных.** Документ активной задачи строится из её brief
  (resolved artifact), как для архивных; если brief ещё не написан — использовать title
  (не падать на отсутствии brief).
- **Пустые области.** Пустой архив/нет активных/нет матчей → `matches: []` (как сейчас),
  не ошибка.
- **Метка области.** В режиме `all` (и желательно во всех) каждый матч несёт
  `scope: active|archived`, чтобы потребитель различал.
- **Слой доступа.** Активные читаются через `Owl::Tasks`/storage role, не прямым FS;
  архив — через `Owl::Archive::Api` (как сейчас). Не нарушать слои.
- **Версионирование.** Новый флаг/поведение — minor bump + CHANGELOG.

# Acceptance criteria

- [ ] `owl recall "<q>" --scope active|archive|all [--json]`; дефолт `archive`
  (back-compat).
- [ ] Корпус `active` строится из brief активных задач (fallback на title без brief);
  `all` = active + archived.
- [ ] Матчи в `all` (и при возможности всегда) помечены `scope: active|archived`.
- [ ] Доступ к активным — через слой задач/storage, к архиву — через Archive::Api.
- [ ] Тесты: scope active/archive/all; дефолт=archive; пустые области; метка scope;
  активная без brief.
- [ ] `bundle exec rspec` зелёный; 100% покрытие затронутых `lib/owl/**/api.rb`;
  RuboCop net-zero.
- [ ] `Owl::VERSION` поднят + CHANGELOG.

# Out of scope

- Семантический/векторный поиск (остаётся tf-idf, без сети).
- Изменение синтаксиса recall кроме `--scope`.
