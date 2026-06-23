# Plan: merge_docs/publish — честность + индекс + shipped-flip

## Goal

Реализовать по `design.md`: (1) flip `design: approved→shipped` в publish
(flip источника ДО копии), (2) генерируемый `docs/README.md`-индекс как пост-шаг
publish, (3) честную прозу `merge_docs`/publish. Контракт `owl publish --json`
расширить аддитивно. step-id `merge_docs` не трогать, KB не строить. Соблюсти
bump+CHANGELOG+100% покрытие `publish/api.rb`.

## Scope

- `lib/owl/publish/internal/status_flipper.rb` (new) + интеграция в backend.
- `lib/owl/publish/internal/docs_index.rb` (new) + интеграция в backend.
- `lib/owl/publish/backends/filesystem.rb` — вызвать flip (до copy) и index
  (после copy), пробросить `design_status` + `index` в результат.
- `lib/owl/publish/api.rb` — расширить возвращаемое значение (аддитивно).
- Проза: `workflows/feature/merge_docs.context.md` +
  `.owl/workflows/{feature,hotfix,refactor}/merge_docs.context.md`; затронутые
  скиллы/доки.
- Версия/CHANGELOG; специи.

## Constraints

- **Аддитивность контракта**: существующие ключи (`results[].action`,
  `step_status`, `dry_run`, коды ошибок) не меняются. Bump **minor**.
- **dry-run чистота**: flip/index/copy не пишут при `--dry-run`.
- **Идемпотентность**: повторный publish на `shipped` — no-op flip; индекс
  побайтно стабилен при том же наборе доков (без таймстемпов в теле).
- **Layering** (`docs/agents/27`): доступ к файлам только через
  `Owl::Storage::Api`; логика в `publish/internal/*`, публично — `publish/api.rb`.
- **Coverage** (`docs/agents/30`): 100% строк `lib/owl/publish/api.rb`.
- **Source/material sync**: править И `workflows/*` источник, И
  `.owl/workflows/*` материализацию; `.claude/` — через `bin/owl upgrade`.
- **Constitution** §7.1: bump `Owl::VERSION` + `CHANGELOG.md` в том же коммите.

## Files to inspect

- `lib/owl/publish/backends/filesystem.rb` (:22 `run` — точка интеграции).
- `lib/owl/publish/internal/publisher.rb` (:56 write_rule, :93 copy_to_target,
  :71 backup — переиспользовать backup-хелпер/паттерн).
- `lib/owl/publish/internal/path_resolver.rb` (resolved source/target пути).
- `lib/owl/publish/api.rb` (форма результата).
- `lib/owl/storage/api.rb` (read/write/list — для скана `docs/` и записи).
- Front-matter паттерн: `lib/owl/artifacts/backends/filesystem.rb`,
  `lib/owl/steps/internal/*` (парс/перезапись YAML front-matter).
- `workflows/feature/merge_docs.context.md` +
  `.owl/workflows/{feature,hotfix,refactor}/merge_docs.context.md`.
- `skills/owl-step-execution/SKILL.md`, `skills/_owl_conventions.md`,
  `skills/owl-orchestrator/SKILL.md` — упоминания publish/merge.
- `README.md`, `REQUIREMENTS.md`, `ARCHITECTURE.md`, `AGENTS.md`, `CLAUDE.md` —
  точечный overselling.
- Существующие специи: `spec/owl/publish/api_spec.rb`,
  `spec/owl/publish/backends/filesystem_spec.rb`,
  `spec/owl/cli/publish_command_spec.rb`,
  `spec/owl/integration/{merge_docs_spec_merge,feature_workflow_full_cycle,hotfix_refactor_merge_docs}_spec.rb`.
- `lib/owl/version.rb`, `CHANGELOG.md`.

## Checklist

1. **StatusFlipper**: `Owl::Publish::Internal::StatusFlipper` — на основе
   resolved-правил находит источник с front-matter `status` enum, содержащим
   `shipped` (практически `design.md`); если `approved` → перезаписать
   `status: shipped` в источнике `tasks/<ID>/design.md` через `Storage::Api`.
   Возвращает признак (`flipped_to_shipped|already_shipped|not_applicable`).
   No-op при dry-run / missing source / уже shipped / нет front-matter.
2. **Backend интеграция flip**: в `Filesystem#run` после PathResolver и ДО
   `Publisher.call` вызвать StatusFlipper (non-dry-run). При `Err` flip —
   вернуть ошибку до копии (не копировать рассинхрон).
3. **Publisher** копирует уже `shipped`-источник → копия согласована
   (изменений в Publisher минимум/нет).
4. **DocsIndex**: `Owl::Publish::Internal::DocsIndex.regenerate(root:,
   dry_run:)` — скан `docs/TASK-*/` через `Storage::Api.list`, собрать
   опубликованные файлы, отрендерить детерминированный `docs/README.md`
   (сортировка по TASK-ID, ссылки + summary из front-matter, без таймстемпов).
   No-op при dry-run. Решение по `.bak` для README зафиксировать (не бэкапить
   генерируемый индекс — воспроизводим).
5. **Backend интеграция index**: после успешной non-dry-run копии вызвать
   `DocsIndex.regenerate`, пробросить `{updated, path}`.
6. **Api/contract**: `publish/api.rb` и backend result добавляют
   `design_status` + `index` (аддитивно). Проверить, что CLI `publish.rb` их
   прозрачно сериализует.
7. **Проза**: переписать `merge_docs.context.md` (источник + 3 материализации)
   — убрать «merge published docs»/«knowledge base», описать публикацию +
   `spec_delta` + реализованные flip и индекс. Точечно поправить скиллы и
   пользовательские доки.
8. **Version/CHANGELOG**: bump `Owl::VERSION` (minor), запись в `CHANGELOG.md`.
9. **Тесты** (см. ниже) зелёные; rubocop по net-delta чист на затронутых файлах.

## Tests and verification

- `spec/owl/publish/api_spec.rb` (расширить): flip apply (`approved→shipped`
  source+copy), dry-run без flip, idempotent (`already_shipped`), no-source →
  `not_applicable`; новые ключи результата.
- `spec/owl/publish/docs_index_spec.rb` (new): README содержит ссылки на все
  `docs/TASK-*/`, dry-run не пишет, детерминизм/идемпотентность (двойной прогон
  → identical bytes).
- `spec/owl/publish/backends/filesystem_spec.rb`: порядок flip→copy, ошибка flip
  не приводит к копии.
- `spec/owl/docs/merge_docs_prose_spec.rb` (new): контекст-файлы не содержат
  запрещённых формулировок («merge published docs», «knowledge base») и
  упоминают flip/index. (Подстроить под существующий паттерн doc-спек, как
  `spec/owl/docs/conventions_*`.)
- Регрессия: `spec/owl/integration/merge_docs_spec_merge_spec.rb`,
  `feature_workflow_full_cycle_spec.rb`,
  `hotfix_refactor_merge_docs_spec.rb` — no-op пути и full cycle зелёные.
- Контракт: существующие `results[].action`/коды ошибок не изменились.
- Команда: `bundle exec rspec` (судить по «0 failures», см.
  reference_owl_repo_health про red-exit), `bundle exec rubocop` net-delta.

## Smoke test

Во временном проекте (feature):

1. Провести задачу до publish; `owl publish TASK --json` →
   `design_status: flipped_to_shipped`, `index.updated: true`.
2. Проверить `tasks/<ID>/design.md` и `docs/<ID>/design.md` оба `status:
   shipped`; `docs/README.md` содержит ссылку на доку.
3. Повторный `owl publish TASK` → `design_status: already_shipped`, README
   побайтно не изменился.
4. `owl publish TASK --dry-run` → ни один файл не изменён (git clean).
5. Задача без `design` (optional missing) → publish не падает, flip
   `not_applicable`, индекс строится по существующим докам.

## Out of scope

- Полноценный KB: агрегация/поиск/`owl docs browse`.
- Отдельная CLI-команда `owl docs index` (возможный follow-up — тонкая обёртка
  над `DocsIndex`).
- Ренейм step-id `merge_docs`.
- Расширение `publishes:`-правил на другие артефакты, кроме текущих.
- Изменение поведения `owl spec merge` / spec-слоя.
