---
status: approved
summary: "Execution plan for the objective verification gate (verify:true step-marker + Owl::Verification engine + complete-gate)."
---

## Goal

Реализовать объективный verification-гейт по design'у: новый домен
`Owl::Verification` запускает `settings.verification.command` и объективно пишет
`verification.md`; шаг с маркером `verify: true` гейтит своё завершение в
`Owl::Steps::Api.complete` на `status == passed`; поведение opt-in и fail-open.
Каждый пункт — конкретное изменение файла, чтобы `implement` не переоткрывал
решений (они в `design`).

## Scope

Owl CLI core (`lib/owl/**`), seeded workflow/context/schema-контент
(`workflows/**`, `schemas/workflow.json`), config-валидация, CLI-поверхность,
тесты, версия/CHANGELOG. Перенос авторства `verification` с `implement` на
`review_code` в seeded `feature`/`hotfix`/`refactor`.

## Checklist

- [ ] `lib/owl/config/internal/validator.rb` — добавить
  `validate_settings_verification(settings['verification'])` и вызвать из
  `validate_settings`. Коды: `invalid_settings_verification_shape`,
  `invalid_settings_verification_command`, `invalid_settings_verification_timeout`.
- [ ] `lib/owl/config/internal/document.rb` — геттер до `settings.verification`
  (`command`, `timeout_seconds`) с дефолтом `timeout_seconds = 1800`.
- [ ] `lib/owl/config/internal/default_template.rb` — добавить закомментированный
  пример `settings.verification.command` в стартовый config (opt-in, по умолчанию
  не задан).
- [ ] `lib/owl/verification/internal/command_runner.rb` — обёртка над
  `Open3.capture3` с таймаутом (`Timeout`/wait-thread kill); `Outcome(exit_code,
  stdout, stderr, timed_out, duration)`. Инъектируется для тестов.
- [ ] `lib/owl/verification/internal/report_writer.rb` — рендер/перезапись
  `tasks/<id>/verification.md`: frontmatter `status` (`passed`/`failed`),
  `## Summary`, `## Commands`, `## Outcomes`, `## Failures or blockers`,
  `## Not run`, `## Residual risks` (по шаблону артефакта verification).
- [ ] `lib/owl/verification/api.rb` — `run(root:, task_id:, command: nil,
  timeout: nil, runner: ...)`: резолвит команду из config при `command: nil`,
  гоняет runner, пишет отчёт, возвращает `Result.ok(status:, exit_code:, command:,
  output_tail:, duration:, timed_out:)` или `Result.err(:verification_command_missing)`.
- [ ] `lib/owl/verification.rb` (+ require в корневом загрузчике `lib/owl.rb`) —
  подключить новый домен.
- [ ] `schemas/workflow.json` — добавить булево поле шага `verify` (default false).
- [ ] `lib/owl/workflows/internal/step_lookup.rb` — внести `verify` в распознаваемые
  поля шага (булево).
- [ ] `lib/owl/verification/internal/gate.rb` — резолвер гейтящего шага по образцу
  `Publish::Internal::StepGate.resolve_step_id` (первый шаг с `verify: true`) +
  `call(...)` возвращающий `{gate_active, status, exit_code, command}`.
- [ ] `lib/owl/steps/api.rb` (`complete`, после `OutputValidator.call`) — если у
  шага `verify: true`: команды нет → warning `verification_gate_inactive`, пройти;
  команда есть → `Owl::Verification::Api.run` → `status != passed` (кроме
  `partial`, который пропускается с warning) → `Result.err(:verification_failed)`
  (шаг остаётся `running`); иначе продолжить штатное завершение.
- [ ] `lib/owl/cli/api.rb` — команда `owl verify TASK-ID [--json]` →
  `{ok, status, exit_code, command, gate_active}`.
- [ ] `lib/owl/cli/internal/help_text.rb` — usage для `owl verify`.
- [ ] `workflows/feature/workflow.yaml` — перенести `creates: [verification]` с
  `implement` на `review_code`; добавить `verify: true` на `review_code`.
- [ ] `workflows/hotfix/workflow.yaml`, `workflows/refactor/workflow.yaml` — то же
  для их `review_code` (если шаг присутствует; иначе пропустить с пометкой).
- [ ] `workflows/feature/steps/implement.context.md` — убрать инструкцию писать
  `verification`; оставить build-фокус.
- [ ] `workflows/feature/steps/review_code.context.md` — описать объективный гейт,
  требование heartbeat перед длинным прогоном.
- [ ] `bin/owl upgrade` (этот dogfooding-репо) — ре-материализовать изменённые
  seeded workflow/context в `.owl/` после правок (иначе live-реестр отстанет).
- [ ] `lib/owl/version.rb` — bump minor (`Owl::VERSION`).
- [ ] `CHANGELOG.md` — запись о фиче в том же коммите.

## Constraints

- Архитектура Backend/Internal/Api (docs/agents/27): FS-доступ только через
  Backend; `Api` — тонкий фасад. Никаких прямых чтений `.owl/`/`tasks/` мимо
  существующих Paths-резолверов.
- `lib/owl/verification/api.rb` и затронутые строки `lib/owl/steps/api.rb` —
  100% построчного покрытия (docs/agents/30). `command_runner` инъектируется,
  чтобы тесты не гоняли реальный сьют.
- Managed workflow'ы кастомизируются клонированием — команда остаётся в config,
  не в YAML.
- Изменение поведения + seeded-контента → bump `Owl::VERSION` (minor) +
  `CHANGELOG.md` в одном коммите (Constitution §7.1).
- fail-open инвариант: проект без `settings.verification.command` ведёт себя как
  до изменения.

## Files to inspect

- `lib/owl/steps/api.rb` (`complete`, `reopen` каскад) — точка гейта.
- `lib/owl/publish/internal/step_gate.rb` — образец резолва шага по маркеру.
- `lib/owl/config/internal/validator.rb`, `document.rb` — паттерн валидации settings.
- `lib/owl/workflows/internal/step_lookup.rb`, `schemas/workflow.json` — поля шага.
- `lib/owl/upgrade/internal/shell_runner.rb` — образец `Open3.capture3`.
- `.owl/artifacts/verification/templates/default.md` — структура отчёта.

## Tests and verification

- `spec/owl/verification/run_command_spec.rb` — exit 0 → passed, ≠0 → failed,
  таймаут → failed; отчёт перезаписан; статус ставит Owl.
- `spec/owl/cli/step_complete_verification_gate_spec.rb` — `failed` блокирует
  complete (exit≠0, `merge_docs` не ready); `passed` проходит; нет команды →
  fail-open + warning; `partial` не блокирует.
- `spec/owl/cli/step_reopen_cascade_spec.rb` — `reopen implement --cascade` после
  провала возвращает граф в pending.
- `spec/owl/config/verification_command_spec.rb` — чтение/валидация
  `settings.verification.*`; команда не из YAML.
- Прогон: `bundle exec rspec` (объективный гейт самого репо после установки
  `settings.verification.command`).

## Smoke test

В тест-проекте задать `settings.verification.command: "false"` (заведомо
ненулевой exit) → `owl step complete TASK review_code` отклоняется с
`verification_failed`; сменить на `"true"` → завершение проходит и `merge_docs`
становится ready. Затем убрать команду → завершение проходит с warning
`verification_gate_inactive`.

## Out of scope

- Per-task override команды (YAGNI для v1).
- Двойной прогон/повторное подтверждение результата агентом.
- Heartbeat *внутри* прогона (возможный follow-up; пока — обязанность
  оркестратора + таймаут команды).
- Гейт готовности (ready-resolver) — гейтим только завершение.
- Изменение `composite_feature` (его `review` валидирует декомпозицию, не код).
