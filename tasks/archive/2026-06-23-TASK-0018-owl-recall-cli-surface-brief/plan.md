# Plan — `owl recall`

## Goal

Реализовать команду `owl recall` и её surface на шаге brief строго по
`tasks/TASK-0018/design.md`: модуль `Owl::Recall` (Api + internal Tokenizer/
CorpusBuilder/Scorer) поверх `Owl::Archive::Api`, CLI-обёртка с JSON-контрактом
`{ok, matches:[{task_id,title,score,snippet}]}`, тонкий surface в
owl-step-discussion, плюс minor-бамп версии и запись в CHANGELOG. Без новых
внешних зависимостей; доступ к корпусу только через Archive::Api.

## Scope

Движок ранжирования + CLI-команда `recall` + surface на brief + version/CHANGELOG.
Один независимо поставляемый ребёнок composite-родителя TASK-0015.

## Constraints

- Чистый Ruby, без сетевых вызовов и новых gem-ов.
- Корпус читается только через `Owl::Archive::Api.list|read` — никаких прямых
  `File.read` в recall.
- `lib/owl/recall/api.rb` — 100% покрытие строк (Конституция §; RSpec-правило).
- Read-only команда: не мутирует репозиторий.
- Детерминизм: при равном score вторичный ключ сортировки `task_id` asc.
- Любое изменение поведения → бамп `Owl::VERSION` + CHANGELOG в том же коммите.

## Files to inspect

- `lib/owl/archive/api.rb` — сигнатуры `list/read` (потребляются CorpusBuilder).
- `lib/owl/archive/internal/archive_reader.rb` — формат данных list.
- `lib/owl/cli/api.rb` — таблица dispatch + образец `dispatch_archive`.
- `lib/owl/cli/internal/commands/archive_list.rb` — образец команды (парсинг,
  result-эмиттер, --root/--json).
- `lib/owl/cli/internal/help_text.rb` — место usage-строки.
- `lib/owl/result.rb` — обёртка ok/error для JSON.
- `lib/owl/version.rb` — текущая версия.
- `skills/owl-step-discussion/SKILL.md` — секция исполнения шага brief.
- существующие `spec/owl/**` — стиль RSpec, фикстуры архива.

## Checklist

- [ ] `lib/owl/recall/internal/tokenizer.rb` — `Owl::Recall::Internal::Tokenizer.tokens(str)`: unicode-downcase, разбиение по `\p{L}\p{N}`, отброс стоп-слов (встроенный ru/en список) и пустых; чистая функция → `Array<String>`.
- [ ] `lib/owl/recall/internal/corpus_builder.rb` — `CorpusBuilder.build(root:)`: `Owl::Archive::Api.list(root:)` → документы `{task_id,title,text}`; `text = title + extract(brief Problem/Goal через Archive::Api.read)`; нет brief → `text=title`.
- [ ] `lib/owl/recall/internal/scorer.rb` — `Scorer.rank(query_tokens:, corpus:, limit:)`: tf-idf score, нормировка по длине, snippet (1 строка ~140 симв., схлопнутые пробелы), сортировка score desc / task_id asc, усечение до limit.
- [ ] `lib/owl/recall/api.rb` — `Owl::Recall::Api.recall(root:, query:, limit: DEFAULT_LIMIT)` оркеструет Tokenizer→CorpusBuilder→Scorer; пустой запрос/корпус → `[]`. 100% покрытие.
- [ ] `lib/owl/cli/internal/commands/recall.rb` — парсинг `owl recall <query> [--limit N] [--root PATH] [--json|--no-json]`, вызов Api, JSON `{ok:true, matches:[...]}`; пустой query → `{ok:true,matches:[]}` exit 0 (не падать).
- [ ] `lib/owl/cli/api.rb` — `require_relative 'internal/commands/recall'`, запись `'recall' => :dispatch_recall` в таблице, метод `dispatch_recall(args, **opts)`.
- [ ] `lib/owl/cli/internal/help_text.rb` — usage-строка `recall  Find similar archived tasks by lexical match (read-only).`
- [ ] `skills/owl-step-discussion/SKILL.md` — в исполнение шага brief добавить вызов `owl recall "<title>" --json` + рендер блока «Похожие архивные задачи» (пусто/ошибка → не блокировать).
- [ ] `lib/owl/version.rb` — minor-бамп `Owl::VERSION`.
- [ ] `CHANGELOG.md` — запись о команде `owl recall` (кросс-задачная память).
- [ ] `spec/owl/recall/api_spec.rb` — контракт + все ветки recall (пустой запрос, пустой корпус, limit, нормальный путь) — 100% api.rb.
- [ ] `spec/owl/recall/ranking_spec.rb` — tf-idf ранжирование, детерминизм при равном score, кириллица.
- [ ] `spec/owl/recall/corpus_spec.rb` — только архивные задачи в корпусе; доступ через Archive::Api (не прямой FS); задача без brief.
- [ ] `spec/owl/cli/recall_command_spec.rb` (или рядом с CLI-спеками) — JSON-форма `{ok,matches}`, `--limit`, пустой результат exit 0.

## Tests and verification

- `bundle exec rspec spec/owl/recall spec/owl/cli/recall_command_spec.rb` — все зелёные.
- Проверить 100% покрытие `lib/owl/recall/api.rb` (правило публичного API).
- `bin/owl recall "<тема архивной задачи>" --json` вручную — непустой ранжированный список на текущем архиве.
- Полный прогон `bundle exec rspec` — без регрессий.
- После правки `skills/owl-*` — `bin/owl upgrade` (синк `.claude/`).

## Smoke test

```
bin/owl recall "semantic artifact validation" --json
# => {ok:true, matches:[{task_id:"TASK-0001", title:"P3: Semantic artifact validation...", score:>0, snippet:"..."}, ...]}
bin/owl recall "" --json
# => {ok:true, matches:[]}   # exit 0, не падает
```

## Out of scope

- Семантический поиск / embeddings.
- Индексация активных (не-архивных) задач.
- Персистентный индекс/кэш на диске.
- Автоматическая правка брифа на основе найденного (recall только подсказывает).
