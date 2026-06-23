---
status: resolved
summary: >-
  Независимое ревью TASK-0017 (hardening verification-гейта). Два новых spec-файла
  реально упражняют subprocess-слой CommandRunner (без заглушки Open3) и все ветки
  CLI owl verify; timeout-кейс доказывает смерть process-group через ESRCH +
  wall-clock и не флачет (3 прогона). Удаление dead-code Gate.resolve_step_id
  подтверждённо безопасно (нет вызовов; живые тёзки в publish/CLI не тронуты).
  Patch-бамп 0.7.0→0.7.1 + CHANGELOG обоснованы. Полный rspec — 1772 примера,
  0 падений; verification/api.rb — 100%; rubocop чист. Скоуп не расползся.
verdict: accepted
ready: true
---

# Review — Harden verification-гейт (TASK-0017)

## Summary

Изменение делает ровно то, что заявлено в brief/design/plan: укрепляет objective
verification-гейт тестами там, где их не было, и убирает один доказанно мёртвый
метод. Поведение гейта не меняется, публичные сигнатуры `Owl::Verification::Api`
не тронуты. Я независимо перечитал diff и оба новых spec-файла, перепроверил
мёртвость удалённого кода grep'ом и прогнал все три проверки (целевой набор,
полный rspec, rubocop). Все сигналы зелёные. Вердикт — **accepted**.

## Findings

Проход по 7 пунктам чеклиста ревью:

1. **Реальный subprocess-слой (не заглушка Open3) — ПОДТВЕРЖДЕНО.**
   `spec/owl/verification/command_runner_spec.rb` вызывает настоящий
   `CommandRunner.run` с реальными `sh -c` командами, без стаба `Open3`/`Timeout`.
   - exit 0 → `exit_code 0`, `timed_out false` (`command_runner_spec.rb:26-31`);
   - exit 3 → `exit_code 3` пробрасывается дословно (`:33-38`);
   - stdout+stderr раздельно захвачены (`:42-48`);
   - timeout → `timed_out:true`/`exit_code:nil` (`:52-70`);
   - сбой spawn (битый `chdir`) → `exit_code:nil` + непустой `stderr` + `timed_out:false`
     (ветка `rescue` в `command_runner.rb:22-26`) (`:73-83`);
   - `duration` ≥ 0 и Numeric (`:85-92`).
   Все шесть требований brief'а покрыты.

2. **Доказательство смерти потомка и анти-флакость — ПОДТВЕРЖДЕНО (надёжно).**
   `command_runner_spec.rb:52-70`: shell записывает свой PID (лидер process-group
   из-за `pgroup: true`) в файл, затем `sleep 5`; раннер вызван с `timeout: 0.5`.
   Доказательство убийства двойное: (а) `wait_dead(pid)` опрашивает
   `Process.kill(0, pid)` до `Errno::ESRCH` в течение 3s (`:13-23, :68`) — это
   реальная проверка, что группа получила TERM; (б) `outcome.duration < 3.0`
   (`:65`) доказывает, что управление вернулось у таймаута (~0.5s), а не у конца
   sleep (5s). Зазор 0.5s vs 5s — большой; межпроцессного зомби-лика нет, т.к.
   `terminate` шлёт `TERM` всей группе (`-pid`). Я прогнал timeout-набор 3 раза
   подряд — `6 examples, 0 failures` каждый раз. Флакость — низкий риск.

3. **Все ветки CLI `owl verify` — ПОДТВЕРЖДЕНО.**
   `spec/owl/cli/verify_command_spec.rb` гоняет через реальный `Owl::Cli::Api.run`
   + StringIO во временном проекте (`with_tmp_project` + `init`/`task create`):
   - нет TASK-ID → `ok:false`, `error.code == invalid_arguments` (`:32-42`,
     ветка `verify.rb:23-27`);
   - команда не задана → `ok:true`, `gate_active:false`, stderr содержит
     `verification_gate_inactive` (`:44-55`, ветка `verify.rb:33/51-59`);
   - команда задана, успех → `gate_active:true`, `status passed`, `exit_code 0`,
     `command` (`:57-72`);
   - команда задана, провал (`exit 1`) → `status failed` без падения CLI (`:74-88`);
   - неизвестная задача `TASK-9999` → `ok:false` структурно
     (`:90-103`, ветка `verify.rb:42`).
   Покрыты все ветки `verify.rb`, включая `run_command` happy/fail и проброс Err.

4. **Удаление dead-code корректно и безопасно — ПОДТВЕРЖДЕНО.**
   Удалён `Owl::Verification::Internal::Gate.resolve_step_id`
   (`lib/owl/verification/internal/gate.rb`, было строки 40-47). Независимо
   проверил `grep -rn resolve_step_id lib spec`: ссылки есть ТОЛЬКО на иные,
   живые тёзки — `Owl::Publish::Internal::StepGate.resolve_step_id`
   (`publish/internal/step_gate.rb:20,56`) и CLI
   `step_id_resolver.rb:74,137` (+ его spec). Копию verification-гейта не вызывал
   никто. `Gate.call` (`gate.rb:26-38`) резолвит `verify: true`-шаги через
   `verify_step?` (`:40-52`) и `resolve_step_id` никогда не использовал —
   удаление поведение не меняет. Публичная сигнатура `Owl::Verification::Api`
   не изменена (diff её не трогает).

5. **Версионирование — ПОДТВЕРЖДЕНО.**
   Изменён `lib/**` (удаление кода в `gate.rb`) → patch-бамп `Owl::VERSION`
   0.7.0 → 0.7.1 (`lib/owl/version.rb`) обоснован по §7.1; CHANGELOG-запись с
   `### Changed` и `### Removed` добавлена в том же изменении
   (`CHANGELOG.md:7-26`). Контракт не менялся → именно patch, корректно.
   `Gemfile.lock` синхронизирован (owl-cli 0.7.1) — ожидаемый version-sync.

6. **Покрытие api.rb 100% сохранено — ПОДТВЕРЖДЕНО.**
   Из `coverage/.resultset.json`: `lib/owl/verification/api.rb` —
   12/12 executable lines (100.0%). `command_runner.rb` — 32/33 (96.97%),
   непокрыта лишь строка 54 (`rescue StandardError; nil` в `terminate` —
   защитный глоток, когда процесс уже мёртв к моменту TERM). Это честно
   зафиксировано в `verification.md` как живой defensive-код, не dead. Ничего
   в `lib/owl/verification/**` не сломано.

7. **Скоуп не расползся — ПОДТВЕРЖДЕНО.**
   Чистка dead-code ограничена `lib/owl/verification/**` (тронут только
   `gate.rb`). Классификация passed/failed/partial, fail-open, формат
   `verification.md` — без изменений (`gate.rb:54-90`, `verify.rb` нетронут).
   Никаких новых публичных команд/методов.

## Resolution

Блокеров нет. Все находки — подтверждающие (verdict по каждому пункту: pass).
Независимая верификация совпала с отчётом `implement`:

- `bundle exec rspec spec/owl/verification spec/owl/cli/verify_command_spec.rb` →
  **23 examples, 0 failures**.
- `bundle exec rspec spec/owl/verification/command_runner_spec.rb` ×3 →
  **6 examples, 0 failures** каждый раз (timeout-кейс не флачет).
- `bundle exec rspec` (полный) → **1772 examples, 0 failures, 1 pending**
  (фрагмент стек-трейса от SimpleCov `at_exit` на некоторых seed'ах при 0
  падений — известный wart репозитория; судим по числу падений).
- `bundle exec rubocop lib/owl/verification spec/owl/verification/command_runner_spec.rb spec/owl/cli/verify_command_spec.rb`
  → **no offenses detected** (7 файлов).
- `coverage/.resultset.json`: `verification/api.rb` 100%.

Артефакт `verification.md` не трогал (он авторен на шаге `implement`).

## Remediation

Не требуется. Изменение готово к merge_docs/commit_push как есть.

## Residual risks

- **`command_runner.rb:54`** (`rescue StandardError; nil` в `terminate`) остаётся
  непокрытым — живой defensive-код для гонки «процесс уже умер к TERM». Низкий
  риск; кандидат на будущее покрытие, не блокер.
- **`report_writer.rb:66`** (ветка run-error в `summary_line`) — живой, но не
  упражняется новыми спеками. Тоже кандидат на покрытие, не риск регрессии.
- **Тайминг timeout-кейса** полагается на реальные часы ОС; зазор 0.5s vs 5s
  большой, риск флакости на экстремально медленном CI — низкий.
- **Unix-only** (`pgroup`/`TERM -pid`) — зафиксировано как ограничение проекта;
  на Windows subprocess-тесты не предназначены.
