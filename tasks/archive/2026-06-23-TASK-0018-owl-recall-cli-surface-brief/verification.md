---
status: passed
summary: >-
  После фикса F1 (клампинг отрицательного --limit) полный прогон 1741 примеров /
  0 падений / 1 pending, exit 0; recall-набор зелёный, rubocop по recall-файлам
  чисто, смоук `owl recall` (реальный, пустой и --limit -1) даёт корректный JSON
  exit 0. recall/api.rb покрыт на 100%.
---

# Verification — `owl recall` (TASK-0018)

## Summary

Честный самоотчёт (объективный gate неактивен — `settings.verification.command`
не сконфигурирован). Все команды прогнаны в рабочем дереве и зелёные:
recall-набор и полный набор без падений, rubocop без замечаний, смоук-сценарии
из plan.md воспроизводят ожидаемый вывод, публичный API recall покрыт на 100%.

## Commands

1. `bundle exec rspec spec/owl/recall spec/owl/cli/recall_command_spec.rb`
2. `bundle exec rspec` (полный набор)
3. `bundle exec rubocop lib/owl/recall lib/owl/cli/internal/commands/recall.rb spec/owl/recall spec/owl/cli/recall_command_spec.rb`
4. `bin/owl recall "semantic artifact validation" --json`
5. `bin/owl recall "" --json`
6. Точное покрытие `lib/owl/recall/api.rb` из `coverage/.resultset.json`.

## Outcomes

1. Recall-набор: `33 examples, 0 failures` (Finished in 0.62s).
2. Полный набор (после фикса F1): `1741 examples, 0 failures, 1 pending`,
   exit 0 (на 1 example больше — добавлена спека на отрицательный `--limit`).
   Pending — заранее помеченный example (не регрессия). Документированный wart
   (ненулевой exit при 0 падениях / интермиттентный SystemStackError) в этом
   прогоне НЕ наблюдался — exit 0, трасс нет.
3. Rubocop: `10 files inspected, no offenses detected` (только pre-existing
   warning'и о миграции плагинов rubocop-performance/rspec — не относятся к
   правкам).
4. Смоук реальный запрос: `{"ok":true,"matches":[...]}`, топ
   `TASK-0001` score `2.439315`, далее по убыванию score; сниппеты
   одно-строчные ≤140 симв., JSON-валидны; exit 0.
5. Смоук пустой запрос: `{"ok":true,"matches":[]}`, exit 0, без трассы.
6. Смоук `owl recall "semantic" --limit -1 --json` (ранее ронял трассу):
   `{"ok":true,"matches":[]}`, exit 0 — F1 исправлен.
7. Покрытие `lib/owl/recall/api.rb`: 100% строк публичного API (клампинг-ветка
   покрыта новой спекой; соответствие docs/agents/30).

## Not run

- Объективный verification-gate `owl step complete` с командой —
  `settings.verification.command` не задан, gate неактивен; статус выставлен
  вручную и честно.
- Нагрузочные/большие корпуса — вне объёма (non-goal brief'а).

## Failures or blockers

- Падений нет. Блокеров нет.
- Ревью-находка F1 (`owl recall --limit -1` ронял `ArgumentError` трассой)
  исправлена в этом же шаге через loop-back в implement (клампинг лимита в
  `Api.recall` + спека) и перепроверена смоуком и полным прогоном.

## Residual risks

- Полный прогон зелёный на этом seed; известный интермиттентный
  SystemStackError из pre-existing circular require может всплыть на других
  seed'ах — судить по числу падений (здесь 0), не по exit-коду.
