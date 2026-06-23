---
status: passed
summary: >-
  Добавлены два spec-файла (реальный subprocess-слой CommandRunner + все ветки
  CLI owl verify) — 11 примеров, 0 падений, timeout-кейсы стабильны на 3
  прогонах. Удалён доказанно мёртвый Gate.resolve_step_id (нет вызовов в
  lib/spec). Полный bundle exec rspec — 1772 примера, 0 падений, 1 pending.
  rubocop по изменённым файлам — чисто. lib/owl/verification/api.rb — 100%.
  Тронут lib/** → patch-бамп 0.7.0 → 0.7.1 + запись в CHANGELOG.
---

# Verification — Harden verification-гейт (TASK-0017)

## Summary

Реализован весь чеклист `plan.md`. Добавлены два новых spec-файла, покрывающих
ранее непокрытые слои objective verification-гейта: реальный subprocess-слой
`Owl::Verification::Internal::CommandRunner` (без заглушки `Open3`) и CLI
`owl verify TASK-ID` (все ветки через `Owl::Cli::Api.run` + StringIO). Dead-code
scan (coverage-непокрытие ∩ grep-нессылаемость) выявил один доказанно мёртвый
метод — `Gate.resolve_step_id` — он удалён. Публичные сигнатуры
`Owl::Verification::Api` (`run`/`gate`/`configured_command` и их kwargs) не
менялись; поведение гейта прежнее.

Поскольку тронут `lib/**` (удаление мёртвого кода), сделан patch-бамп
`Owl::VERSION` 0.7.0 → 0.7.1 с записью в `CHANGELOG.md` в том же изменении
(Конституция §7.1).

## Commands

- `bundle exec rspec spec/owl/verification/command_runner_spec.rb spec/owl/cli/verify_command_spec.rb`
- `bundle exec rspec spec/owl/verification/command_runner_spec.rb` (×3, проверка флакости timeout-кейсов)
- `bundle exec rspec` (полный прогон с coverage)
- `bundle exec rubocop spec/owl/verification/command_runner_spec.rb spec/owl/cli/verify_command_spec.rb lib/owl/verification/internal/gate.rb lib/owl/version.rb`
- `ruby -Ilib -r./lib/owl/verification/internal/command_runner -e '...CommandRunner.run(command: "sh -c \"exit 3\"", chdir: ".", timeout: 5)...'` (smoke)

## Outcomes

- Новые спеки: `11 examples, 0 failures` (6 — command_runner, 5 — verify CLI).
- Стабильность timeout-кейса: 3 прогона подряд `6 examples, 0 failures` — не флачет
  (зазор: `timeout 0.5s` vs `sleep 5`, убитость потомка проверяется через
  `Errno::ESRCH` на сохранённый PID + `duration < 3.0`).
- Полный прогон: `1772 examples, 0 failures, 1 pending`.
- rubocop по 4 изменённым/новым файлам: `no offenses detected`.
- `lib/owl/verification/api.rb`: `12/12 executable lines covered (100.0%)`.
- Smoke subprocess-слоя: `[3, false]` (exit_code 3, timed_out false) — ожидаемо.

### Dead-code outcome

- **Удалён:** `Owl::Verification::Internal::Gate.resolve_step_id`
  (`lib/owl/verification/internal/gate.rb`). Два сигнала совпали: строки 43–47
  не покрыты полным прогоном И `grep -rn resolve_step_id lib spec` не нашёл ни
  одного вызова этого метода (живая копия, используемая publish-гейтом, — это
  отдельный `Owl::Publish::Internal::StepGate.resolve_step_id`). Verification-гейт
  резолвит `verify: true`-шаги напрямую в `call`/`verify_step?`. Удаление не
  меняет наблюдаемого поведения — полный набор остался зелёным.
- **НЕ удалено (live, untested-but-defensive):**
  - `command_runner.rb:54` — `rescue StandardError; nil` в `terminate` (защитный
    глоток ошибки, когда процесс уже мёртв к моменту TERM). Живой defensive-код,
    не dead.
  - `report_writer.rb:66` — ветка `summary_line` для run-error (exit_code nil,
    не timed_out). Живой код (используется при сбое spawn), просто не упражняется
    текущими спеками; не dead — не трогали.

### Версия

- Тронут `lib/**` → **patch**-бамп `Owl::VERSION` 0.7.0 → 0.7.1 + запись в
  `CHANGELOG.md` (Changed: hardening-тесты; Removed: dead `Gate.resolve_step_id`).
  Контракт `api.rb` не менялся, потому patch.

## Not run

- Windows-совместимость subprocess-тестов (`pgroup` / `TERM -pid`) — Unix-only,
  зафиксировано как ограничение в brief/design/plan; не запускалось намеренно.

## Failures or blockers

- Нет. 0 падений в новых спеках и в полном прогоне.
- Примечание (известный wart репозитория): SimpleCov-`at_exit` на некоторых
  seed'ах печатает фрагмент стек-трейса/может дать ненулевой exit-код при 0
  падений. Судим по числу падений (`0 failures`), а не по exit-коду — как
  предписывает шаг.

## Residual risks

- `command_runner.rb:54` и `report_writer.rb:66` остаются непокрытыми (живой
  defensive/run-error код, вне scope двух новых spec-файлов) — кандидаты на
  будущее покрытие, не риск регрессии гейта.
- Timeout-кейс полагается на реальные тайминги ОС; зазор большой (0.5s vs 5s),
  риск флакости на крайне медленном CI — низкий.
