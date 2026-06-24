# Goal

Добавить `owl recall --scope active|archive|all`, расширив корпус tf-idf на активные
задачи (их brief), сохранив дефолт `archive` (back-compat).

# Scope

- `Owl::Recall::Api.recall` + `CorpusBuilder` — параметр `scope`, источник активных.
- CLI `recall` — опция `--scope`.
- Метка `scope: active|archived` в матчах.
- Тесты + bump `Owl::VERSION` (minor) + CHANGELOG.

# Constraints

- `lib/owl/recall/api.rb` под 100% покрытием `**/api.rb` — все новые ветки покрыть.
- Дефолт `scope=archive`: без флага поведение НЕ меняется (brief-step оркестратора и
  прочие вызовы intact).
- Слои: активные читать через `Owl::Tasks` (list/index) + brief через storage/artifact
  resolve, НЕ прямым FS; архив — через `Owl::Archive::Api` (как сейчас).
- Активная задача без brief → документ из title (не падать).
- Пустые области/нет матчей → `[]` (как сейчас), не ошибка.
- tf-idf без сети; синтаксис recall не меняется кроме `--scope`.

# Checklist

1. **CorpusBuilder.** `build(root:, scope: 'archive')`:
   - `archive` → текущая логика (Archive::Api), каждый doc помечается `scope: 'archived'`.
   - `active` → список активных задач (`Owl::Tasks` list/index, исключая
     терминальные/архивные), для каждой строится doc из brief (resolve+read через
     storage/artifact) с fallback на title; помечается `scope: 'active'`.
   - `all` → объединение active + archived.
   - Невалидный scope → понятная ошибка/дефолт (выбрать: ошибка `invalid_scope`).
2. **Recall::Api.recall.** Добавить `scope: 'archive'` kwarg; прокинуть в CorpusBuilder;
   каждый match несёт `scope`. Сохранить сигнатурную совместимость (kwarg с дефолтом).
3. **Scorer.** Прокинуть `scope` из doc в match-результат (или сохранить doc-метаданные
   до выдачи). Минимально менять ранжирование (idf считается по итоговому корпусу).
4. **CLI recall.** Опция `--scope active|archive|all` (дефолт archive); прокинуть в Api;
   в JSON-выводе матчи несут `scope`.
5. **Тесты:** scope active находит активную задачу по тексту brief; archive — прежнее;
   all — обе области с корректными метками; дефолт=archive; активная без brief
   (fallback title); пустые области; невалидный scope. Покрыть новые ветки
   `recall/api.rb` до 100%.
6. Bump `Owl::VERSION` (minor) + `CHANGELOG.md`.

# Files to inspect

- `lib/owl/recall/api.rb` — сигнатура recall (+scope).
- `lib/owl/recall/internal/corpus_builder.rb` — источник корпуса (+active).
- `lib/owl/recall/internal/scorer.rb` — прокинуть scope в match.
- `lib/owl/tasks/api.rb` (list/query — источник активных), `lib/owl/storage`/
  `lib/owl/artifacts` (resolve+read brief активной задачи).
- `lib/owl/cli/internal/commands/recall.rb` (+`--scope`), `cli/api.rb` (если нужно),
  `help_text.rb` (recall — bare-arg, без subcommands).
- `spec/owl/recall/**`, `spec/owl/cli/**`.
- `lib/owl/version.rb`, `CHANGELOG.md`.

# Tests and verification

- Юнит/CLI на все сценарии (см. checklist 5).
- `bundle exec rspec` зелёный (после — `git checkout README.md`).
- 100% покрытие `recall/api.rb`; RuboCop net-zero.

# Smoke test

```
owl recall "tracker status labels" --scope active --json   # → активная задача в матчах, scope:active
owl recall "commit push" --scope archive --json            # → архивные (как раньше)
owl recall "index lock" --scope all --json                 # → обе области, метки scope
owl recall "x" --json                                       # → дефолт archive (без изменений)
```

# Out of scope

- Семантический/векторный поиск. assignees/due/epics. Прочие изменения recall.
