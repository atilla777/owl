---
status: shipped
summary: >-
  Реализационный дизайн `owl recall`. Новый модуль `Owl::Recall` с публичным
  `Api.recall(root:, query:, limit:)` и приватным internal (Tokenizer,
  CorpusBuilder поверх Owl::Archive::Api, Scorer на tf-idf/token-overlap,
  чистый Ruby). CLI-команда `owl recall` в lib/owl/cli/internal/commands/recall.rb
  + регистрация в dispatch-таблице и help_text. Surface на шаге brief —
  тонкий вызов `owl recall "<title>"` из owl-step-discussion. Контракт JSON:
  {ok, matches:[{task_id,title,score,snippet}]}. minor-бамп Owl::VERSION +
  CHANGELOG.
---

# Design — `owl recall` (реализационный)

## Context

Наследует архитектурный baseline родителя TASK-0015
(`tasks/TASK-0015/design.md`): слой `Backend → Internal → Api` помодульно,
доступ к корпусу архивных задач только через `Owl::Archive::Api`
(`list(root:)`, `read(root:, task_id:, artifact_key:)`), CLI как тонкая
обёртка над Api.

Целевые файлы/точки:

- Новый модуль `lib/owl/recall/` (`api.rb` + `internal/`).
- Потребляет `Owl::Archive::Api` (`lib/owl/archive/api.rb`) — уже существует.
- CLI: новый `lib/owl/cli/internal/commands/recall.rb`; правки в
  `lib/owl/cli/api.rb` (require + `'recall' => :dispatch_recall` + метод
  `dispatch_recall`) и `lib/owl/cli/internal/help_text.rb` (usage-строка).
- Surface: правка `skills/owl-step-discussion/SKILL.md` (+ материализованная
  копия `.claude/skills/owl-step-discussion` через `owl upgrade`).
- Версия: `lib/owl/version.rb` (minor-бамп) + `CHANGELOG.md`.

## Decision

### Модуль `Owl::Recall`

**`lib/owl/recall/api.rb` — `Owl::Recall::Api`** (публичный, 100% покрытие строк):

```
DEFAULT_LIMIT = 10

def self.recall(root:, query:, limit: DEFAULT_LIMIT)
  # 1. tokens_q = Tokenizer.tokens(query); вернуть [] если пусто
  # 2. corpus = CorpusBuilder.build(root:)   # [{task_id,title,text}]
  # 3. matches = Scorer.rank(query_tokens: tokens_q, corpus: corpus, limit: limit)
  # 4. вернуть Array<Hash> {task_id:, title:, score:, snippet:}
  #    отсортировано score desc, затем task_id asc; усечено до limit
end
```

Api не знает про JSON/печать/exit-коды — это слой CLI.

**`lib/owl/recall/internal/`:**

- `tokenizer.rb` — `Owl::Recall::Internal::Tokenizer.tokens(string)`:
  unicode-downcase, разбиение по не-словам (`\p{L}\p{N}` как словесные,
  поддержка кириллицы), отброс пустых и стоп-слов (короткий встроенный список
  ru/en); возврат `Array<String>`. Чистая функция, без состояния.
- `corpus_builder.rb` — `Owl::Recall::Internal::CorpusBuilder.build(root:)`:
  `Owl::Archive::Api.list(root:)` → для каждой архивной задачи документ
  `{task_id, title, text}`, где `text = title + " " + extract(brief)`;
  `extract` берёт секции `## Problem` и `## Goal` из
  `Owl::Archive::Api.read(root:, task_id:, artifact_key: 'brief')`. Если brief
  нет/недоступен — `text = title`. Никаких прямых `File.read`.
- `scorer.rb` — `Owl::Recall::Internal::Scorer.rank(query_tokens:, corpus:,
  limit:)`: tf-idf по корпусу. idf по документам корпуса; score документа =
  Σ (tf(term,doc) * idf(term)) по term ∈ query_tokens ∩ doc_tokens;
  нормировка по длине документа для честности. Возвращает топ-`limit` с
  `snippet` (см. ниже). Детерминирован: при равном score вторичный ключ
  `task_id` asc.
  - **snippet:** первая строка `text` документа, содержащая совпавший терм,
    усечённая до ~140 симв., схлопнутые пробелы (без переносов — безопасно для
    JSON-строки). Если совпавшей строки нет — начало `title`.

### CLI `owl recall`

`lib/owl/cli/internal/commands/recall.rb` (по образцу `commands/archive_list.rb`):
парсит `owl recall <query> [--limit N] [--root PATH] [--json|--no-json]`,
зовёт `Owl::Recall::Api.recall`, печатает через общий result-эмиттер
`{ok: true, matches: [...]}`. Пустой/тривиальный query → `{ok:false, error:{code:"empty_query", ...}}` exit 1 ИЛИ `{ok:true,matches:[]}` exit 0 — выбрать `matches:[]`/exit0 (мягко, не падать; brief требует «не падать трассой»). Регистрация в `lib/owl/cli/api.rb`: `require_relative 'internal/commands/recall'`, запись `'recall' => :dispatch_recall` в таблице, метод `dispatch_recall(args, **opts)`. Usage в `help_text.rb`.

### Surface на шаге brief

`skills/owl-step-discussion/SKILL.md`: в секцию исполнения шага `brief` добавить
шаг «перед сбором требований вызвать `owl recall "<task.title>" --json` и, если
`matches` непуст, показать автору блок **«Похожие архивные задачи»**
(`task_id` · `title` · `snippet`, топ-N); пустой результат — одна строка
«похожих архивных задач не найдено»; шаг не блокируется при любой ошибке
recall». Логика скоринга здесь не дублируется. После правки `skills/owl-*`
прогнать `bin/owl upgrade` для синка `.claude/`.

### Версия

`Owl::VERSION` minor-бамп (новая команда). Запись в `CHANGELOG.md` тем же
коммитом (Конституция §7.1).

## Alternatives

- **Прямой `File.read` архива в CorpusBuilder.** Отвергнуто: нарушает слой;
  `Owl::Archive::Api` уже даёт list/read.
- **Bag-of-words без idf (чистый overlap).** Проще, но шумит на частых
  токенах; tf-idf дешёв и заметно качественнее — берём tf-idf.
- **Команда `owl archive recall`.** Отвергнуто (родительский design): recall —
  отдельная ответственность, чище самостоятельным модулем.
- **Жёсткая ошибка на пустой запрос.** Отвергнуто: brief требует не падать;
  возвращаем `matches:[]` exit 0.
- **Персистентный индекс.** Отложено: прямой проход дёшев на текущем масштабе;
  Api-контракт стабилен и переживёт добавление кэша.

## Risks

- **Качество ранжирования / кириллица.** Митигация: tf-idf + unicode-
  токенизация; spec-кейсы на ru-заголовки и на разведение релевантного/нерелевант.
- **Связанность surface↔CLI.** owl-step-discussion только зовёт `owl recall`,
  не парсит архив. Митигация: surface тонкий; контрактная проверка наличия
  блока/строки.
- **Стабильность вывода.** Вторичный ключ сортировки `task_id` для детерминизма.
- **Покрытие api.rb 100%.** Все ветки `recall` (пустой запрос, пустой корпус,
  limit, нормальный путь) покрыть в spec/owl/recall/api_spec.rb.
- **Backward-compat JSON.** Форма `{ok, matches:[{task_id,title,score,snippet}]}`
  становится публичным контрактом — зафиксирована в спеках; изменения по SemVer.

## API

**Ruby:**

```
Owl::Recall::Api.recall(root:, query:, limit: Owl::Recall::Api::DEFAULT_LIMIT)
  => Array<{ task_id: String, title: String, score: Float, snippet: String }>
     # score desc, затем task_id asc; усечено до limit
     # query пустой/только стоп-слова, пустой архив, нет совпадений => []
     # корпус ТОЛЬКО через Owl::Archive::Api (list/read)
```

**CLI:**

```
owl recall <query> [--limit N] [--root PATH] [--json|--no-json]
```

**JSON (default):**

```json
{ "ok": true,
  "matches": [
    { "task_id": "TASK-0007", "title": "Wire spec layer ...",
      "score": 0.82, "snippet": "...совпавший фрагмент..." }
  ] }
```

- `matches`: score desc, вторично `task_id` asc; `--limit N` усекает (default 10).
- Пустой корпус / нет совпадений / пустой запрос → `{ "ok": true, "matches": [] }`, exit 0.
- Read-only: никаких мутаций репозитория.

**Surface (шаг brief):** owl-step-discussion вызывает `owl recall "<task.title>"
--json`, рендерит топ как «Похожие архивные задачи»
(`task_id` · `title` · `snippet`); пусто → явная строка; ошибка recall не
блокирует шаг.

**Тесты (план):** `spec/owl/recall/api_spec.rb` (контракт + ветки, 100% api),
`spec/owl/recall/ranking_spec.rb` (tf-idf, детерминизм, кириллица),
`spec/owl/recall/corpus_spec.rb` (только архив, доступ через Archive::Api),
CLI-спек на JSON-форму, контрактная проверка surface.
