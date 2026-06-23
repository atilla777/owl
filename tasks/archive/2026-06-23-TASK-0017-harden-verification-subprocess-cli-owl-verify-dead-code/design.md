---
status: shipped
summary: >-
  Два новых spec-файла + консервативная чистка dead-code. (1)
  spec/owl/verification/command_runner_spec.rb гоняет РЕАЛЬНЫЙ
  CommandRunner.run на коротких подпроцессах (exit-коды, timeout→kill
  process-group, сбой spawn, захват вывода). (2) spec/owl/cli/verify_command_spec.rb
  покрывает все ветки `owl verify` через Owl::Cli::Api.run с StringIO.
  (3) Dead-code в lib/owl/verification/** удаляется ТОЛЬКО по подтверждению
  (coverage-непокрытие + grep-нессылаемость), без изменения публичных
  сигнатур api.rb. Версия: patch-бамп, если тронут lib/**; иначе только спеки.
---

# Design — Harden verification-гейт (тесты subprocess-слоя + CLI + чистка)

## Context

Verification-гейт (`Owl::Verification`, TASK-0012) уложен слоями:

- `api.rb` — `run`, `gate`, `configured_command` (публичный, 100% покрытие).
- `internal/engine.rb` — оркестрация: config → CommandRunner → classify →
  ReportWriter.
- `internal/command_runner.rb` — **subprocess-слой**: `Open3.popen3(pgroup:true)`
  + `Timeout` + `terminate` (`Process.kill('TERM', -pid)`) + `drain`. Возвращает
  `Outcome(exit_code, stdout, stderr, timed_out, duration)`.
- `internal/gate.rb`, `internal/report_writer.rb`.

Текущая `spec/owl/verification/run_command_spec.rb` инъектирует фейковый раннер
в `Api.run`, поэтому реальный `command_runner.rb` и CLI `owl verify` напрямую не
покрыты. Образцы реальных subprocess-тестов в репозитории: верхний слой gem
(`Open3`), а инъекция/StringIO-CLI — как в `run_command_spec.rb`
(`Owl::Cli::Api.run(argv:, stdout:, stderr:, env:, cwd:)`).

`brief` зафиксировал: реальные мини-процессы для subprocess-слоя; прямые
CLI-спеки; чистка dead-code только в verification-модуле; без смены поведения.

## Decision

### 1. `spec/owl/verification/command_runner_spec.rb` — реальный subprocess-слой

Прямые юнит-тесты `Owl::Verification::Internal::CommandRunner.run(command:,
chdir:, timeout:)` на настоящих коротких командах (Unix, `sh -c`):

- **exit-код:** `sh -c 'exit 0'` → `exit_code 0`, `timed_out false`;
  `sh -c 'exit 3'` → `exit_code 3`.
- **stdout/stderr:** `sh -c 'echo out; echo err 1>&2'` → захвачены в
  `stdout`/`stderr`.
- **timeout + kill:** долгая команда, пишущая PID-маркер, с малым `timeout`
  (например, 0.5s vs `sleep 5`) → `timed_out true`, `exit_code nil`; проверить,
  что дочерний процесс/группа завершены (нет живого потомка — например, через
  попытку `Process.kill(0, pid)` → `Errno::ESRCH`, либо что общий wall-clock
  ≈ timeout, а не ≈ sleep). Использовать `chdir: Dir.pwd` (валидный).
- **сбой spawn:** `chdir:` на несуществующий путь → `exit_code nil`,
  `stderr` непуст, `timed_out false` (ветка `rescue` в `run`).
- **duration:** `Outcome.duration` — неотрицательное число.

Запас по времени подобрать так, чтобы не флаковать на CI (короткий timeout,
заведомо долгий sleep). Без инъекций — это и есть смысл harden.

### 2. `spec/owl/cli/verify_command_spec.rb` — все ветки CLI

Через `Owl::Cli::Api.run(argv: ['verify', ...], stdout:, stderr:, env:, cwd:)`
со `StringIO` (как `run_command_spec.rb`), во временном проекте (`owl init` +
`task create`):

- **нет TASK-ID:** `argv ['verify']` → `ok:false`, `error.code
  invalid_arguments`.
- **гейт неактивен:** команда не задана → `ok:true`, `gate_active:false`,
  stderr содержит `verification_gate_inactive`.
- **активный гейт:** задать `settings.verification.command` на тривиальную
  успешную команду (например, `sh -c 'exit 0'`) → `ok:true`,
  `gate_active:true`, `status` из exit-кода, поля `exit_code`/`command`.
  При провальной команде (`exit 1`) → `status` failed, без падения CLI.
- **проброс ошибки движка:** случай, где `Api.run` возвращает Err (например,
  отсутствующая задача) → `ok:false` со структурной ошибкой.

### 3. Чистка dead-code — консервативно и подтверждённо

Удалять из `lib/owl/verification/**` ТОЛЬКО код, доказанно мёртвый, по двум
сигналам вместе:

- **coverage:** строки, не покрытые полным `bundle exec rspec` (после добавления
  новых спек) — кандидаты;
- **grep-нессылаемость:** метод/ветка/поле, на которые нет ссылок ни в `lib/`,
  ни в `spec/`.

Guard-rails:

- **НЕ менять публичные сигнатуры `api.rb`** (`run/gate/configured_command` и их
  kwargs `command:`/`timeout:`/`runner:`) — это контракт; их «недёрганье»
  продакшен-вызовами не делает их dead-code (это точки инъекции/тестируемости).
  Если кажется, что `timeout:`-проброс не упражняется — закрыть его ТЕСТОМ
  (передать `timeout:`/`command:` явно в спеке), а не удалять.
- Удаление допускается для внутренних неиспользуемых методов/ветвей. Если после
  scan ничего доказанно-мёртвого не найдено — зафиксировать это в
  verification-отчёте (новые тесты могли как раз закрыть «подозрительные»
  строки), удаление не выдумывать.

После добавления спек `command_runner_spec`/`verify_command_spec` многие ранее
непокрытые строки `command_runner.rb`/`verify.rb` станут покрытыми — что само по
себе и есть «harden» (часть «подозрений на dead-code» — на деле untested-but-live).

### 4. Версия

- Если чистка тронула `lib/owl/verification/**` (любой `lib/**`) → **patch**-бамп
  `Owl::VERSION` + запись в `CHANGELOG.md` тем же коммитом (Конституция §7.1):
  только удаление мёртвого кода/тесты, контракт не меняется.
- Если в итоге меняются ТОЛЬКО `spec/**` (dead-code не нашёлся) → бамп НЕ нужен
  (spec/** вне scope §7.1). Решение принять по факту в `implement`.

## Alternatives

- **Заглушка Open3 для subprocess-тестов.** Отвергнуто в brief: не проверяет
  реальные timeout/kill/spawn — т.е. именно то, ради чего harden.
- **Тестировать CLI через прямой вызов модуля `Commands::Verify.run`** вместо
  `Cli::Api.run`. Отвергнуто: интеграция через `Cli::Api.run` ближе к реальному
  пути и согласована с `run_command_spec.rb`.
- **Агрессивное удаление «неупражняемых» kwargs api.rb.** Отвергнуто: это смена
  публичного контракта (breaking), а не чистка dead-code; вместо удаления —
  покрыть тестом.
- **Чистка dead-code по всему репо.** Вне объёма (brief: только verification).

## Risks

- **Флакость timeout-тестов** на медленном CI. Митигация: большой зазор
  (короткий timeout vs длинный sleep), проверка «убит» через `ESRCH`/wall-clock,
  без жёстких таймингов.
- **Зомби/утечка процессов** в самих тестах. Митигация: полагаться на
  `terminate` (TERM группе) + проверка отсутствия живого потомка; не плодить
  фоновые процессы.
- **Ошибочное удаление живого кода.** Митигация: два сигнала (coverage+grep) и
  полный зелёный прогон; при сомнении — покрыть тестом, не удалять.
- **Случайная смена контракта `api.rb`.** Митигация: явный guard-rail «не менять
  публичные сигнатуры»; 100% покрытие api.rb сохраняется.
- **Unix-only** (`pgroup`/`TERM -pid`). Зафиксировано как ограничение; проект
  Unix.

## API

Публичный контракт verification НЕ меняется:

```
Owl::Verification::Api.run(root:, task_id:, command: nil, timeout: nil, runner:)
Owl::Verification::Api.gate(root:, task_id:, step_id:, runner:)
Owl::Verification::Api.configured_command(root:)
```

CLI `owl verify TASK-ID [--root PATH] [--json]` — поведение прежнее; добавляются
лишь тесты на его существующие ветки (`invalid_arguments`,
`gate_active:false`+warning, `gate_active:true`, проброс Err).

**Новые артефакты — только тесты (+ возможное удаление dead-code):**
`spec/owl/verification/command_runner_spec.rb`,
`spec/owl/cli/verify_command_spec.rb`. Никаких новых публичных команд/методов.
