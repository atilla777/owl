---
status: approved
summary: >-
  Укрепить objective verification-гейт тестами там, где его сейчас нет: реальный
  subprocess-слой `Owl::Verification::Internal::CommandRunner` (exit-коды,
  timeout → TERM всей process-group, сбой spawn) покрыть РЕАЛЬНЫМИ мини-
  процессами (`sh -c 'exit N'`, `sleep` с малым timeout, битый chdir), а
  CLI-команду `owl verify` — прямыми спеками на все ветки (нет TASK-ID →
  invalid_arguments; нет команды → gate_active:false fail-open; активный гейт;
  проброс ошибки движка). Плюс убрать dead-code в lib/owl/verification/**. Без
  изменения поведения (hardening/refactor). Объём чистки — только
  verification-модуль.
---

# Brief — Harden verification-гейт: тесты subprocess-слоя + CLI `owl verify`, чистка dead-code

## Problem

Objective verification gate — это гарантия, что статус «passed» авторит Owl из
реального exit-кода команды (`settings.verification.command`), а не агент. Но
самый отказоопасный слой этой гарантии не покрыт прямыми тестами:

- **`Owl::Verification::Internal::CommandRunner`** (`command_runner.rb`) —
  единственное место, где реально запускается команда через `Open3.popen3`
  (`pgroup: true`), с `Timeout`, и где runaway-процесс убивается сигналом
  `TERM` всей **process-group** (`Process.kill('TERM', -pid)`). Существующая
  спека `spec/owl/verification/run_command_spec.rb` гоняет движок
  (`Verification::Api.run`) с **инъектированным фейковым раннером**, поэтому
  реальное поведение Open3/timeout/kill/спавна НЕ проверяется.
- **CLI `owl verify TASK-ID`** (`commands/verify.rb`) не имеет прямой
  спеки. Его ветки — нет TASK-ID (`invalid_arguments`), нет настроенной команды
  (`gate_active:false`, fail-open warning), активный гейт (статус из exit-кода),
  проброс ошибки движка — покрыты только косвенно через gate-на-`step complete`
  (`step_complete_verification_gate_spec`), не на самой команде.
- В `lib/owl/verification/**` есть **мёртвый/неиспользуемый код** (название
  задачи), который вводит в заблуждение и должен быть убран.

Последствие: ключевой механизм доверия к «green verification» опирается на
непокрытый subprocess-слой; регрессия в timeout/kill/exit-обработке прошла бы
незамеченной.

## Goal

Поднять надёжность verification-гейта без изменения его поведения:

1. **Тесты subprocess-слоя `CommandRunner` РЕАЛЬНЫМИ мини-процессами**
   (выбрано вместо заглушки Open3 — иначе не проверяется именно то, ради чего
   делается harden):
   - exit-код успешной команды (`sh -c 'exit 0'`) и провальной (`exit N`)
     пробрасывается в `Outcome.exit_code`;
   - долгая команда (`sleep`) с малым `timeout` → `timed_out: true`,
     `exit_code: nil`, и дочерний процесс/группа убиты (не остаётся зомби/
     runaway);
   - сбой запуска (например, несуществующий `chdir`) → `exit_code: nil` с
     сообщением в `stderr` (run error, отличён от ненулевого exit теста);
   - захват stdout/stderr.
2. **Прямые CLI-спеки `owl verify`** на все ветки: `invalid_arguments` без
   TASK-ID; `gate_active:false` + warning при незаданной команде (fail-open);
   `gate_active:true` со статусом/exit_code/command при настроенной команде;
   проброс структурной ошибки движка.
3. **Чистка dead-code** в `lib/owl/verification/**` (и только там): удалить
   реально неиспользуемые методы/ветки/поля, подтвердив, что они мертвы.

### Не входит в объём (Non-goals)

- Изменение поведения гейта (классификация passed/failed/partial, fail-open,
  формат `verification.md`) — это hardening, не редизайн.
- Чистка dead-code вне `lib/owl/verification/**`.
- Настройка `settings.verification.command` для этого/других проектов.
- Кроссплатформенность Windows: `pgroup`/`TERM -pid` — Unix-only; тесты
  ориентированы на Unix (как и весь проект).

## Scenarios

### Requirement: тесты реального subprocess-слоя

The system SHALL покрывать `Owl::Verification::Internal::CommandRunner.run`
тестами на реальных коротких подпроцессах, проверяющими exit-код, timeout с
убийством process-group и сбой запуска.

#### Scenario: exit-код пробрасывается
- WHEN `CommandRunner.run` выполняет `sh -c 'exit 3'` с достаточным timeout
- THEN `Outcome.exit_code == 3`, `timed_out == false`
- AND `exit 0` даёт `exit_code == 0`
- TEST: spec/owl/verification/command_runner_spec.rb

#### Scenario: timeout убивает runaway-процесс
- WHEN команда (`sleep 5`) превышает малый `timeout` (например, 0.5s)
- THEN `Outcome.timed_out == true`, `exit_code == nil`
- AND подпроцесс/группа завершены сигналом TERM (не остаётся работающего
  потомка)
- TEST: spec/owl/verification/command_runner_spec.rb

#### Scenario: сбой запуска отличён от провала теста
- WHEN запуск невозможен (несуществующий `chdir`)
- THEN `Outcome.exit_code == nil` и `stderr` непуст (run error), `timed_out == false`
- TEST: spec/owl/verification/command_runner_spec.rb

### Requirement: прямые CLI-спеки owl verify

The system SHALL покрывать команду `owl verify TASK-ID` прямыми спеками на все её
ветки.

#### Scenario: нет TASK-ID
- WHEN `owl verify` вызвана без позиционного TASK-ID
- THEN команда возвращает `ok:false`, `error.code == invalid_arguments`
- TEST: spec/owl/cli/verify_command_spec.rb

#### Scenario: гейт неактивен (fail-open)
- WHEN `settings.verification.command` не задан
- THEN `ok:true`, `gate_active:false`, на stderr — `verification_gate_inactive` warning
- TEST: spec/owl/cli/verify_command_spec.rb

#### Scenario: активный гейт авторит статус из exit-кода
- WHEN команда задана и выполняется для задачи
- THEN `ok:true`, `gate_active:true`, поля `status`/`exit_code`/`command` из движка
- AND ошибка движка пробрасывается как структурная (`ok:false`)
- TEST: spec/owl/cli/verify_command_spec.rb

### Requirement: удаление dead-code без смены поведения

The system SHALL удалить только реально неиспользуемый код из
`lib/owl/verification/**`, не меняя наблюдаемого поведения гейта.

#### Scenario: мёртвый код убран, поведение прежнее
- WHEN из `lib/owl/verification/**` удалён неиспользуемый метод/ветка/поле
- THEN весь существующий verification-набор остаётся зелёным
- AND публичное поведение `owl verify`/гейта не меняется
- TEST: spec/owl/verification (существующие + новые) зелёные

## Edge cases

- **Нулевой/очень малый timeout** — корректно классифицируется как timeout, без
  гонки/зависания теста.
- **Команда пишет много в stdout перед таймаутом** — drain/kill не виснет; тест
  не флакует (захват в потоках).
- **Сигнал недоступен** (процесс уже умер к моменту kill) — `terminate` глотает
  ошибку, не падает.
- **Флакость по времени:** timeout-кейсы используют запас по времени
  (короткий timeout vs заведомо долгий `sleep`), чтобы не флаковать на CI.
- **Удаляемый dead-code оказался живым** — отлавливается падением существующих
  спек/полным прогоном; удалять только подтверждённо мёртвое.
- **`pgroup`/`TERM -pid` Unix-only** — тесты не предназначены для Windows
  (зафиксировано как ограничение).

## Acceptance criteria

1. Есть `spec/owl/verification/command_runner_spec.rb`, гоняющий РЕАЛЬНЫЙ
   `CommandRunner.run` на коротких подпроцессах: exit-код (0 и ненулевой),
   timeout → `timed_out:true`/`exit_code:nil`/убитый потомок, сбой spawn →
   `exit_code:nil`+stderr; захват stdout/stderr.
2. Есть `spec/owl/cli/verify_command_spec.rb`, покрывающий все ветки `owl verify`
   (invalid_arguments, gate_active:false+warning, gate_active:true+поля, проброс
   ошибки движка).
3. Dead-code в `lib/owl/verification/**` удалён; подтверждено, что он
   неиспользуем; поведение гейта не изменилось.
4. Если правки затронули `lib/owl/verification/api.rb` — его 100% покрытие
   сохранено (`docs/agents/30_...`).
5. Полный `bundle exec rspec` зелёный (0 failures), rubocop чист; timeout-тесты
   не флакуют (запас по времени).
6. Если менялся код в scope бампа (`lib/**`) — бамп `Owl::VERSION` (patch, т.к.
   только тесты + удаление dead-code без смены контракта) + запись в
   `CHANGELOG.md` тем же коммитом (Конституция §7.1). Если меняются только спеки
   — бамп не требуется (spec/** вне scope); решение зафиксировать в design/plan
   по факту того, трогается ли `lib/**`.
7. Edge cases выше либо покрыты, либо явно зафиксированы как ограничения.
