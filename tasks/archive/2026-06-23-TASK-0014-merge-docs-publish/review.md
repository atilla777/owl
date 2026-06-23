---
status: resolved
summary: "Self-review TASK-0014: честный publish (flip approved→shipped до копии, генерируемый docs/README.md-индекс, аддитивный JSON-контракт, честная проза merge_docs). Багов не найдено; все AC покрыты, тесты зелёные, rubocop чист, покрытие publish/api.rb 100%."
verdict: accepted
ready: true
---

# Review

## Summary

Ревью изменения, делающего `owl publish` (шаг `merge_docs`) честным:

- `Publish::Internal::StatusFlipper` переводит источник
  `tasks/<ID>/design.md` `approved → shipped` ДО копирования, поэтому
  источник и опубликованная копия согласованы.
- `Publish::Internal::DocsIndex` пересобирает детерминированный
  `docs/README.md`-индекс после non-dry-run publish.
- JSON-контракт `owl publish` расширен аддитивно (`design_status`,
  `index`); существующие ключи (`results[].action`, `step_status`,
  `dry_run`, коды ошибок) не тронуты.
- Проза `merge_docs.context.md` (источник + 3 материализованных варианта)
  и README приведены к реальности (без «merge published docs» / «knowledge
  base»).
- Версия `0.4.0 → 0.5.0` + запись в `CHANGELOG.md` + `Gemfile.lock`.
- step-id `merge_docs` НЕ переименован; полноценный KB НЕ строится.

Реализация чистая, хорошо структурированная (Backend → Internal модули),
весь файловый доступ идёт через `Owl::Storage::Api`. Все требования и
сценарии из `brief.md` имеют покрывающие тесты, и они зелёные.

## Findings

Реальных багов не обнаружено. Проверены все приоритетные риски ревью:

1. **Чистота dry-run (главный риск) — OK.** На dry-run `StatusFlipper.call`
   сразу возвращает `not_applicable` (ничего не пишет), `Publisher`
   возвращает результат с `dry_run: true` без записи, а
   `DocsIndex.regenerate` возвращает `updated: false` до любой записи.
   Подтверждено тестами `api_spec` («does not flip on dry-run»: источник
   остаётся `approved`, `docs/README.md` не создан) и `docs_index_spec`.

2. **Порядок flip — OK.** В `publish_resolved` flip выполняется ПЕРЕД
   копией; ошибка flip (`design_flip_failed`) возвращается до вызова
   `Publisher`, поэтому десинхрона источник/копия не возникает. Источник и
   копия оба заканчиваются `shipped` (тест «flips approved design to
   shipped … expect(source).to eq(published)»).

3. **Идемпотентность — OK.** Повторная публикация уже `shipped` design даёт
   `already_shipped` (no-op). `DocsIndex` детерминирован: сортировка по
   `link`, отсутствие таймстемпов; тест «two runs … yield identical bytes».

4. **No-source / spec-less — OK.** Отсутствующий optional design ⇒
   `not_applicable` без падения; `Publisher` отдаёт
   `skipped_missing_source`; путь `no_spec_delta` и существующие
   `results[].action` / коды ошибок не изменены (back-compat).

5. **Безопасность переписи front-matter — OK.** `rewrite_status` меняет
   только строку `status:` внутри ведущего блока `---…---` (regex привязан
   к `^status:[ \t]*approved`), остальной документ остаётся байт-в-байт.
   Детектор «flippable» управляется enum схемы артефакта, а не именем
   файла: `design` (enum `[draft, approved, shipped]`) флипается, `spec`
   (enum `[draft, active]`) — нет. В реальном `feature/workflow.yaml`
   `design.storage.path` == `publishes[0].from` (`{{task.id}}/design.md`),
   поэтому в проде flip действительно срабатывает (не только в синтетических
   тестах).

6. **Layering — OK.** Весь I/O через `Owl::Storage::Api`; дополнения в
   allowlist `no_direct_fs_spec.rb` (`docs_index.rb`, `status_flipper.rb`)
   оправданы — это `Pathname`-математика путей (`relative_path_from`,
   `+`), а не прямой файловый доступ.

7. **Проза — OK.** Запрещённые формулировки («merge published docs»,
   «knowledge base», «база знаний») отсутствуют во всех 4 вариантах
   `merge_docs.context.md` и в README (repo-wide grep чист, кроме самих
   spec-доков задачи); flip + индекс задокументированы; источник и
   материализованные копии согласованы. Guard-тест
   `merge_docs_prose_spec.rb` фиксирует это.

8. **Версия/CHANGELOG/lock — OK.** `version.rb` 0.5.0, `CHANGELOG.md`
   `[0.5.0] - 2026-06-23`, `Gemfile.lock` `owl-cli (0.5.0)` — согласованы.

Незначительное наблюдение (не дефект): `DocsIndex` корректно исключает
бэкап-файлы (`design.md.bak.<timestamp>` имеют extname != `.md`) и сам
`docs/README.md` (лежит в корне `docs/`, а сканируются только `docs/TASK-*/`),
поэтому индекс не загрязняется и не самоссылается.

## Resolution

Все находки положительные — изменений в коде по итогам ревью не требуется.
Acceptance criteria из `brief.md` выполнены; объективная проверка (rspec,
rubocop, покрытие) пройдена — см. `verification.md`. Вердикт: **accepted**.

## Remediation

Не требуется.

## Residual risks

- Нет. Контракт расширен аддитивно; back-compat сохранён; шаг `merge_docs`
  не переименован.
