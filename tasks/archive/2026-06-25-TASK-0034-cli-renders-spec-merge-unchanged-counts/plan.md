---
status: approved
summary: "spec_apply.rb: +unchanged в JSON. spec_merge.rb: +unchanged на верх json_payload, +unchanged-строка в summary (nil-safe). Регрессии в spec_apply_diff/spec_merge command specs. patch 0.17.1→0.17.2."
---

# Goal

Сделать `unchanged`-счётчики видимыми в `owl spec apply --json`, `owl spec merge
--json` (верхний уровень) и `owl spec merge --no-json` (summary). Только CLI-слой.

# Scope

- `lib/owl/cli/internal/commands/spec_apply.rb` — `unchanged` в JSON payload.
- `lib/owl/cli/internal/commands/spec_merge.rb` — `unchanged` в json_payload (верх)
  + unchanged-строка в summary.
- `lib/owl/version.rb` + `CHANGELOG.md` — patch bump 0.17.1 → 0.17.2.

# Constraints

- Не трогать `Owl::Specs` (движок/Api) — только презентация CLI.
- nil-safe: graceful no-op merge (`merge: nil`) не должен падать и не печатает
  unchanged-строку.
- Аддитивно (back-compat JSON).
- rspec зелёный; покрытие `**/api.rb` без регрессий; RuboCop net-zero.
- Constitution §7.1: patch bump VERSION + CHANGELOG в том же коммите.

# Files to inspect

- `lib/owl/cli/internal/commands/spec_apply.rb` (#emit → JsonPrinter.success хэш).
- `lib/owl/cli/internal/commands/spec_merge.rb` (#json_payload, #print_merge,
  #emit_summary; ветка no_spec_delta).
- `lib/owl/specs/api.rb` (apply/merge_task — подтвердить ключ `unchanged`/`merge`).
- `spec/owl/cli/spec_apply_diff_command_spec.rb` (куда добавить apply-JSON-регрессию).
- `spec/owl/cli/spec_merge_command_spec.rb` (no-json summary + json регрессии;
  есть тест на 'delta: added 1' под --no-json — рядом).

# Checklist

- [ ] `spec_apply.rb#emit`: добавить `unchanged: value[:unchanged]` в хэш
      `JsonPrinter.success`.
- [ ] `spec_merge.rb#json_payload`: добавить `unchanged: value.dig(:merge,
      :unchanged)` на верхний уровень.
- [ ] `spec_merge.rb` summary: в `print_merge` (или новый `print_unchanged`,
      вызываемый из `emit_summary` после `print_merge`) печатать
      `  unchanged: added %d  modified %d  removed %d` из `merge[:unchanged]`
      (через `.to_i`, нули по умолчанию). Только при наличии `merge`-хэша.
- [ ] `CHANGELOG.md` (Added/Changed): CLI теперь показывает unchanged-счётчики —
      `spec apply --json`, `spec merge --json` (верх. уровень), `spec merge
      --no-json` (summary). Завершает TASK-0029 honest-counts.
- [ ] `lib/owl/version.rb`: 0.17.1 → 0.17.2.

# Tests and verification

- [ ] spec_apply CLI: повторный `apply --json` → payload содержит `unchanged`
      с ожидаемыми счётчиками (напр. added:1 на втором применении).
- [ ] spec_merge CLI `--json`: payload содержит `unchanged` на верхнем уровне.
- [ ] spec_merge CLI `--no-json`: summary включает строку `unchanged: added …`.
- [ ] no-op merge (`no_spec_delta`) под `--no-json` → без unchanged-строки, без
      падения (регрессия существующего no-op теста сохраняется).
- [ ] `bundle exec rspec` зелёный, 0 failures; покрытие `**/api.rb` без регрессий.
- [ ] `bundle exec rubocop` на тронутых файлах net-zero.

# Smoke test

```
# применить дельту дважды, второй раз — всё no-op:
owl spec apply DOMAIN --delta D.md --json | jq .unchanged   # ненулевые счётчики
owl spec merge TASK --json | jq .unchanged                  # верхний уровень
owl spec merge TASK --no-json                               # строка 'unchanged: …'
```

# Out of scope

- Изменение движка merge/apply и подсчёта unchanged (TASK-0029 уже сделал).
- Прочие spec-команды (diff/trace/validate/show) — у них нет unchanged.
- per-task lock / P3 / F2.2.
