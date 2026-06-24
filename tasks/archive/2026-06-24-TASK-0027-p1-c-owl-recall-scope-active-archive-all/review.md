---
status: resolved
summary: "owl recall --scope active|archive|all реализован чисто: дефолт archive сохраняет back-compat, активные читаются через слой задач/артефакт/storage, каждый матч несёт scope, invalid_scope покрыт; rspec зелёный, coverage-гейт пройден, rubocop net-zero."
verdict: accepted
ready: true
---

# Summary

Самопроверка кода P1-C — `owl recall --scope active|archive|all`. Цель брифа/плана:
распространить tf-idf-поиск с архива на активные задачи, сохранив дефолтное поведение
(`archive`). Реализация полностью соответствует брифу, плану и явным точкам ревью; реальных
дефектов не найдено. Вердикт — **accepted**.

Изменения (прод): `lib/owl/recall/api.rb` (kwarg `scope:` + `SCOPES` + ветка
`invalid_scope`), `lib/owl/recall/internal/corpus_builder.rb` (ветки archive/active/all +
чтение активных через слой), `lib/owl/recall/internal/scorer.rb` (проброс `scope` в match),
`lib/owl/cli/internal/commands/recall.rb` (`--scope` + обработка `Result::Err`),
`help_text.rb`, `version.rb` (0.13.0→0.14.0), `CHANGELOG.md`. Тесты: api_spec, corpus_spec,
recall_command_spec. `Gemfile.lock` — синхронизация версии gem (0.13.0→0.14.0), ожидаемо.

# Findings

Проверены все пункты фокуса ревью; каждый подтверждён кодом и тестом.

1. **Дефолт = archive (back-compat) — OK.** `recall(root:, query:, limit:, scope: 'archive')`:
   kwarg с дефолтом `'archive'`. Беззфлаговый вызов оркестратора (brief-step recall)
   проходит ровно прежний путь `CorpusBuilder.build(root:, scope: 'archive')` →
   `archived_documents` через `Owl::Archive::Api`. Тест `defaults to archive, excluding
   active tasks` (api_spec) и `defaults to --scope archive` (cli) фиксируют, что активные
   исключены и метка `archived`. Severity: none.

2. **Scope active читается через слой, не raw FS — OK.** `active_documents` →
   `Owl::Tasks::Api.list` (индексный roster) → фильтр `active_entries` (исключает
   `archived|abandoned|done`) → `active_brief` через `Owl::Artifacts::Api.resolve`
   (резолв пути, проверка `descriptor.value[:exists]`) → `Owl::Storage::Api.read(path:)`.
   Ни одного `File.read`/`Dir` в файле. Подтверждено backend-контрактом: resolve возвращает
   дескриптор с `:path`/`:exists` (`task_artifact_resolver` build_descriptor). Layering-тест
   `reads active briefs through the tasks + artifact/storage layer` (corpus_spec) с
   `verify_partial_doubles` спайит все три facade-вызова. Severity: none.

3. **Активная задача без brief не падает — OK.** `active_brief` возвращает `''` при
   `descriptor.err?` ИЛИ `!descriptor.value[:exists]` ИЛИ `body.err?`; `document` делает
   fallback `text = title`. Тесты `falls back to the title for an active task without a
   brief` (api_spec) и `falls back to the title when an active task has no brief`
   (corpus_spec). Severity: none.

4. **Метка scope в каждом матче — OK.** `document` помечает `scope: 'archived'|'active'`;
   `Scorer#prepare` и `#score_doc` протягивают `scope` в результат; CLI `emit` кладёт
   `scope` в payload. Тесты на обе области (`scope all` сортирует `%w[active archived]`) на
   уровне api и cli. Severity: none.

5. **Invalid scope — error path реально покрыт — OK.** Валидация живёт в `Recall::Api`
   (`return invalid_scope(scope) unless SCOPES.include?(scope.to_s)`), возвращает
   `Owl::Result.err(code: :invalid_scope, ...)`. CLI прокидывает сырую строку и сюрфейсит
   `Result::Err` через `JsonPrinter.failure` (exit 1) — не ограничивает enum в OptionParser,
   поэтому путь обработки ошибки в CLI исполняется тестом. Покрыто: `returns an
   invalid_scope error for an unknown scope` (api_spec, проверяет code+details[:allowed]) и
   `reports invalid_scope (exit 1)` (cli). CorpusBuilder `else []` — защитный, тоже покрыт
   (`returns [] for an unrecognised scope`). Severity: none.

6. **Coverage / версия — OK.** Suite exit 0 ⇒ SimpleCov-гейт (`/lib/owl/(.+/)?(api|result).rb`
   ≥100% строк) зелёный, включая расширенный `recall/api.rb`. `Owl::VERSION` 0.13.0→0.14.0
   (MINOR — новая фича, корректно по SemVer), CHANGELOG `[0.14.0]` добавлен. Severity: none.

7. **Пустые области → [], tf-idf офлайн — OK.** Пустая active-область →
   `recall(... scope: 'active') == []` (тест). Никаких новых сетевых вызовов/гемов;
   токенизатор и scorer не тронуты по сути (только проброс scope). Severity: none.

**Замечание (не дефект):** загрузка `lib` печатает пред-существующие warnings о circular
require (archive→tasks→…→backend_resolver). Цепочка присутствовала до задачи
(см. memory «Owl repo health warts»); новые `require_relative` в corpus_builder не вводят
новую циклическую зависимость и не влияют на тесты (suite exit 0).

# Resolution

Все пункты разрешены без изменений кода — каждый findings подтверждён как корректный и
покрыт тестом. Открытых блокеров нет. `status: resolved`, `verdict: accepted`.

# Remediation

Не требуется.

# Residual risks

- Circular-require warnings при загрузке `lib` остаются (пред-существующий wart, не в
  скоупе этой задачи).
- `tasks/index.yaml` несёт рабочее изменение от текущей задачи — ожидаемо, не дефект.
