---
status: passed
summary: >-
  Терминальная безопасность реализована и проверена: abandon чистит current-указатель,
  явный доступ к мёртвой задаче отдаёт task_terminal, owl next без аргумента
  проваливается в auto_select, TERMINAL_STATUSES сведён к одному источнику.
  Вся доставка (archive→commit_push) сохранена. 2027 примеров зелёные, RuboCop чист.
---

# Summary

Реализованы все пункты чеклиста плана для TASK-0043 (внутренняя bug-fix про
терминальную безопасность задач):

- Введён единый источник истины `Owl::Tasks::Internal::TaskStatuses::TERMINAL`
  (`%w[archived abandoned done]`); `availability_scanner` и `ready_scanner`
  переиспользуют одну и ту же замороженную константу (проверено `equal?`).
  Шаговый `completion_gate` (`%w[done skipped]`) НЕ тронут.
- `AbandonWriter` теперь чистит current-указатель через
  `Archive::CurrentResetter.reset_if_matches` (паритет с `Deleter`). Очистка
  стоит ДО идемпотентного early-return, поэтому повторный abandon чинит
  протухший указатель.
- `TaskResolver.from_current` проваливается в `auto_select`, когда задача из
  указателя «мертва» для оркестрации; явный id остаётся отдельной веткой.
- Общий guard `TaskSupport.reject_if_terminal` подключён к
  `next`/`status`/`ready-steps`/`instructions`: явный «мёртвый» id → структурная
  ошибка `task_terminal` с ненулевым CLI-exit (1). Reject применяется ТОЛЬКО к
  явно переданному id.
- `Owl::VERSION` поднят 0.22.1 → 0.23.0 (minor), добавлена запись в `CHANGELOG.md`.

Важное уточнение реализации (см. «Residual risks»): «терминальность для
оркестрации» сделана тоньше, чем чистая проверка статуса. Задача считается
мёртвой для guard/fallback, если она `abandoned` (отменена) ИЛИ её workflow уже
завершён (все шаги `done`/`skipped`). `archived`-задача в середине доставки
(между шагом `archive`, который выставляет статус `archived`, и финальным
`commit_push`) НЕ отвергается — иначе ломалась бы вся доставка feature/hotfix.

# Commands

- `bundle exec rspec` (полный прогон) → 2027 examples, 0 failures, 1 pending.
- Точечные спеки: `api_abandon_spec`, `api_terminal_spec`, `terminal_status_spec`,
  `task_statuses_spec`, `task_resolver_spec`, `task_terminal_guard_spec`,
  `archive/api_spec` → зелёные.
- `bundle exec rubocop` по всем 19 изменённым файлам → no offenses detected.
- Ручной e2e в tmp-проекте: abandon чистит указатель → `task current`
  = `no_current_task`; явный `next/status/ready-steps/instructions` на abandoned
  → `task_terminal`, exit=1; `next` без аргумента при протухшем указателе →
  `no_available_task` (без dispatch по мёртвой задаче); `next TASK-X` на
  archived-задаче в середине доставки → `dispatch_step commit_push`.

# Outcomes

- **Подтверждение ревьюера (шаг `review_code`).** Независимо переисполнено:
  `bundle exec rspec` → 2027 examples, 0 failures, 1 pending; `bundle exec
  rubocop` по 12 изменённым lib-файлам → no offenses detected; SimpleCov-гейт
  `spec_helper.rb` подтвердил 100% line coverage для всех `lib/owl/**/api.rb`
  (+ `result.rb`). Результаты implement-прогона воспроизведены полностью.
- Все сценарии и acceptance-критерии brief покрыты RSpec-тестами.
- `lib/owl/**/api.rb` сохраняют 100% покрытие строк (SimpleCov-гейт не выдал ни
  одного файла ниже 100%).
- Регрессий нет: единственный изначально упавший на черновой реализации тест
  (`archive/api_spec` — `owl status` по archived-задаче в середине доставки) стал
  зелёным после уточнения правила терминальности, без правки самого теста.

# Not run

- Реальные `git commit`/`git push` не запускались — это отдельный шаг
  `commit_push` workflow, вне scope шага implement.
- Полный прогон под несколькими параллельными клонами не воспроизводился:
  очистка указателя — локальное per-clone состояние (`.owl/local/`), гонок не
  вносит.

# Failures or blockers

Блокеров нет. Все проверки зелёные.

# Residual risks

- **Отклонение от буквальной формулировки brief по `archived`.** Brief требовал
  отвергать любой явный терминальный id, включая `archived`. Буквальная
  реализация ломала переход `archive → commit_push` во всех seeded delivery-
  workflow (шаг `archive` выставляет статус `archived` ДО финального
  `commit_push`; оркестратор добирается до `commit_push` через `owl next TASK-X`).
  Поэтому guard/fallback отвергают `archived`/`done` только когда workflow реально
  завершён (все шаги done/skipped); `abandoned` отвергается всегда. Это сохраняет
  цель brief (не «протекать» мёртвой задачей) и не ломает доставку. Решение
  задокументировано в `CHANGELOG.md` и вынесено в Open follow-ups отчёта для
  ратификации на шаге review_code.
- **Будущий статус `done`.** Сейчас ни один поток не пишет задачный статус
  `done` (это TASK-0044 — авто-закрытие на финальном шаге). Логика
  forward-compatible: `done` с завершённым workflow → отвергается.
