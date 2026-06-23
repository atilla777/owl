# Plan — Harden verification-гейт

## Goal

По `tasks/TASK-0017/design.md`: добавить два spec-файла (реальный subprocess-слой
`CommandRunner` + все ветки CLI `owl verify`) и консервативно удалить
подтверждённый dead-code в `lib/owl/verification/**`, не меняя поведения гейта и
публичных сигнатур `api.rb`. Patch-бамп версии — только если тронут `lib/**`.

## Scope

Тесты subprocess-слоя + CLI `owl verify` + чистка dead-code строго в
`lib/owl/verification/**`. Без редизайна гейта.

## Constraints

- Subprocess-тесты — РЕАЛЬНЫЕ короткие команды (`sh -c`), без заглушки Open3.
- Не флаковать: большой зазор по времени для timeout-кейсов.
- НЕ менять публичные сигнатуры `Owl::Verification::Api` (`run/gate/configured_command`).
- Dead-code удалять только по двум сигналам: coverage-непокрытие + grep-нессылаемость; при сомнении — покрыть тестом, не удалять.
- `lib/owl/verification/api.rb` остаётся 100% покрытым.
- Если меняется `lib/**` → patch-бамп `Owl::VERSION` + CHANGELOG в том же коммите; если только `spec/**` → бамп не нужен.
- Unix-only тесты (pgroup/TERM -pid) — зафиксировать как ограничение.

## Files to inspect

- `lib/owl/verification/internal/command_runner.rb` — subject subprocess-тестов (run/execute/collect/terminate/drain/elapsed).
- `lib/owl/cli/internal/commands/verify.rb` — ветки CLI (invalid_arguments/inactive/run_command/error).
- `lib/owl/verification/api.rb`, `internal/engine.rb`, `internal/gate.rb`, `internal/report_writer.rb` — кандидаты dead-code + контракт.
- `spec/owl/verification/run_command_spec.rb` — образец инъекции + CLI-StringIO (`Owl::Cli::Api.run`).
- `spec/owl/cli/step_complete_verification_gate_spec.rb` — образец настройки `settings.verification.command` во временном проекте.
- `lib/owl/config/api.rb` / `owl config set` — как задать `settings.verification.command` в спеке.

## Checklist

- [ ] `spec/owl/verification/command_runner_spec.rb` — реальные подпроцессы:
  - [ ] `sh -c 'exit 0'` → `exit_code 0`, `timed_out false`; `sh -c 'exit 3'` → `exit_code 3`.
  - [ ] `sh -c 'echo out; echo err 1>&2'` → stdout/stderr захвачены.
  - [ ] долгая команда (`sleep 5`) + малый timeout (~0.5s) → `timed_out true`, `exit_code nil`, потомок убит (проверка через `Errno::ESRCH` на сохранённый PID, либо wall-clock ≈ timeout ≪ sleep).
  - [ ] несуществующий `chdir` → `exit_code nil`, `stderr` непуст, `timed_out false` (ветка rescue).
  - [ ] `Outcome.duration` — неотрицательно.
- [ ] `spec/owl/cli/verify_command_spec.rb` — через `Owl::Cli::Api.run` + StringIO во временном проекте:
  - [ ] нет TASK-ID → `ok:false`, `invalid_arguments`.
  - [ ] команда не задана → `ok:true`, `gate_active:false`, stderr ~ `verification_gate_inactive`.
  - [ ] команда задана (`sh -c 'exit 0'`) → `ok:true`, `gate_active:true`, `status`/`exit_code`/`command`; провальная (`exit 1`) → `status` failed без падения.
  - [ ] ошибка движка (например, неизвестная задача) → `ok:false` структурно.
- [ ] **Dead-code scan**: полный прогон с coverage → выписать непокрытые строки в `lib/owl/verification/**`; пересечь с grep-нессылаемыми методами/ветвями/полями. Удалить только подтверждённо мёртвое (внутреннее), не трогая api.rb-сигнатуры. Если ничего доказанно-мёртвого нет — зафиксировать в verification.md (новые тесты закрыли «подозрения»).
- [ ] Если тронут `lib/**` (dead-code удалён): `lib/owl/version.rb` — patch-бамп; `CHANGELOG.md` — запись (harden verification: тесты subprocess + CLI; удалён dead-code). Иначе — пропустить бамп и отметить причину.

## Tests and verification

- `bundle exec rspec spec/owl/verification spec/owl/cli/verify_command_spec.rb` — зелёные; timeout-кейсы стабильны (несколько прогонов).
- Полный `bundle exec rspec` — 0 failures (судить по числу падений, не exit-коду — известный wart); coverage по `lib/owl/verification/api.rb` = 100%.
- `bundle exec rubocop` по новым/изменённым файлам — чисто.
- Если удалён код в `lib/**` — подтвердить, что полный прогон остаётся зелёным (код был мёртв).

## Smoke test

```
# реальный subprocess-слой:
ruby -r./lib/owl/verification/internal/command_runner -e '
o = Owl::Verification::Internal::CommandRunner.run(command: "sh -c \"exit 3\"", chdir: ".", timeout: 5)
p [o.exit_code, o.timed_out]'   # => [3, false]

# CLI fail-open:
bin/owl verify TASK-XXXX --json   # без команды => {ok:true, gate_active:false} + warning
```

## Out of scope

- Изменение поведения/классификации гейта, формата `verification.md`, fail-open.
- Dead-code вне `lib/owl/verification/**`.
- Изменение публичных сигнатур `Owl::Verification::Api`.
- Windows-совместимость subprocess-тестов.
