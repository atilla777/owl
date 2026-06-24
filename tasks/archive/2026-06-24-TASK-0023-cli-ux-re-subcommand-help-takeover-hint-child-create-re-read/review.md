---
status: resolved
summary: "Три CLI-UX фикса (subcommand-help, takeover-hint, child-create re-read) реализованы корректно, аддитивно и без регрессий; тесты на все три, gate-покрытие api.rb держится, версия и CHANGELOG в норме."
verdict: accepted
ready: true
---

# Summary

Самопроверка кода для TASK-0023 (три CLI-UX фикса из полевого отчёта `re`). Все три
фикса соответствуют брифу/плану и acceptance criteria, реализованы аккуратно, не
ломают существующие контракты и покрыты тестами. Verdict: **accepted**.

# Findings

## FF1 — subcommand help (`lib/owl/cli/api.rb`, `lib/owl/cli/internal/help_text.rb`)

- Перехват `group_help_request?` в `dispatch_command` срабатывает строго перед
  `send(group, …)` и только когда (a) группа есть в `HelpText::GROUP_SUBCOMMANDS` и
  (b) реальной подкоманды нет (пустой `args` либо только `--help`/`-h`/`--json`).
  Конкретный неизвестный verb (`owl step bogus`) даёт `args.all?` → false, проходит
  насквозь в групповой диспетчер и по-прежнему возвращает `unknown_command` (exit 1).
  **Регрессии нет** — подтверждено живым прогоном (`owl step bogus` → exit 1).
- Help-перехват **не может затенить валидную подкоманду**: любой конкретный verb (даже
  валидный) не равен `--help`/`-h`/`--json`, поэтому `group_help_request?` → false и
  команда исполняется как раньше. Перехват ловит только «пусто или только флаги».
- Группы вне реестра (`archive`, `recall`, `commit-push`) — bare-arg, намеренно
  отсутствуют в `GROUP_SUBCOMMANDS`; их позиционное поведение сохранено (тест
  «does not treat a bare-arg group (archive) as a subcommand group»). Ключи
  `GROUP_SUBCOMMANDS` ⊂ `GROUP_DISPATCHERS`, расхождений нет.
- JSON-режим возвращает структурный `{ ok, command, subcommands }` в stdout;
  человекочитаемый usage идёт в stderr с exit 0. `owl --help` обрабатывается раньше в
  `run` и не затронут (подтверждено).

## FF3 — takeover hint (`lib/owl/tasks/internal/claim_service.rb`, `lib/owl/cli/internal/commands/task_claim.rb`)

- Хинт строго **аддитивный**. `running_step` вычисляется только при `opts[:steal]`
  (иначе `nil`); `takeover_hint` возвращает `{}` когда running-шага нет, поэтому
  существующие поля/успех/exit `finalize_claim` не меняются для обычного claim и для
  steal без running-шага. Подтверждено тестом «omits the adopt hint … no running step»
  (`not_to have_key(:hint)` / `:running_step`).
- CLI `task_claim` подмешивает `running_step`+`hint` в JSON и дублирует строкой в
  stderr только при наличии `result.value[:hint]` — поведение по умолчанию неизменно.
- `lib/owl/tasks/api.rb` не менялся (claim — чистая делегация), его 100%-gate не
  затронут.

## FF4 — child-create re-read (`lib/owl/tasks/internal/child_creator.rb`)

- `refresh_payload` вызывается **только** на ветке с `--brief` (после `seed_brief`).
  Ветка без `--brief` (`return create_result if brief_body.nil?`, строка 52) не
  затронута — поведение без `--brief` неизменно.
- Re-read через `TaskReader`; при ошибке re-read — graceful fallback на исходный
  `create_result`. Возвращаемый payload отражает `brief: done`. Подтверждено на уровне
  сервиса и CLI (тесты FF4).

## Версионирование

- `Owl::VERSION` 0.9.0 → 0.10.0 (MINOR — новые affordances, корректно по SemVer).
- `CHANGELOG.md` содержит секцию `[0.10.0] - 2026-06-24` с Added (FF1, FF3) и Fixed
  (FF4). `Gemfile.lock` синхронизирован.

# Resolution

Дефектов не найдено. Все находки — подтверждения корректности; статус **resolved**,
verdict **accepted**. Открытых блокеров нет.

# Remediation

Не требуется — изменения принимаются как есть.

# Residual risks

- Тексты `GROUP_SUBCOMMANDS` — статический реестр; при добавлении новых подкоманд их
  нужно вручную дополнять (help может разойтись с реальным набором verb'ов). Низкий
  риск, чисто косметический; не блокер для этой задачи.
- Downstream-замечание для `commit_push`: untracked `tasks/TASK-0024/` — отдельная
  задача и **не должна** попасть в этот коммит; рабочее изменение `tasks/index.yaml`
  и 2 пред-существующих rubocop-оффенса в `spec/owl/cli/api_spec.rb:490` (TD-141) —
  вне scope, не дефекты.
