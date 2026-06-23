# Goal

Реализовать read-only команду верхнего уровня `owl next [TASK-ID] --json` через
новый домен `Owl::Orchestration`, чей `NextActionResolver` композирует
существующие Tasks/Workflows/Steps/Instructions API и возвращает дискриминированный
`action.kind ∈ {dispatch_step, handoff_composite, stop_blocked, done,
no_available_task}` (все — exit 0, без мутаций). Затем ужать дублирующую прозу
лестницы в `skills/owl-orchestrator`/`skills/owl-cli` до вызова команды, обновить
специи, bump `Owl::VERSION` (minor) + `CHANGELOG.md`.

# Scope

- Новый домен `Owl::Orchestration` (`api.rb` + `internal/next_action_resolver.rb`).
- Новая CLI-команда `owl next` (`lib/owl/cli/internal/commands/next.rb` + регистрация).
- Переиспользование общего резолв-ладдера (current → auto-select) без третьей копии.
- Правка скиллов `owl-orchestrator` и `owl-cli` (ужать прозу лестницы).
- Версия + CHANGELOG.

# Constraints

- Read-only: команда не берёт claim, не стартует шаги, не пишет в `.owl/`/`tasks/`.
- Слоистость `docs/agents/27_*`: `Api` — тонкий фасад без бизнес-логики, логика в
  `Internal`; FS только через существующие доменные API, не напрямую.
- Back-compat: JSON-контракты `task available`, `ready-steps`, `instructions`,
  `step show` не меняются.
- Если затронут `lib/owl/**/api.rb` — 100% покрытие линий (`docs/agents/30_*`);
  держим `api.rb` тонким, логику в `Internal`.
- `action.kind` — стабильное множество; расширение только аддитивно.
- Правка `skills/**` обязывает bump `Owl::VERSION` + запись в `CHANGELOG.md` в том
  же коммите (Constitution §7.1).

# Files to inspect

- `lib/owl/cli/api.rb` — реестр `SIMPLE_COMMANDS`/`TASK_SUBCOMMANDS`, паттерн dispatch.
- `lib/owl/cli/internal/commands/instructions.rb`, `.../task_available.rb`,
  `.../task_support.rb` — образец команды + `resolve_root`.
- `lib/owl/instructions/internal/payload_builder.rb` — резолв-ладдер + `lookup_skill`.
- `lib/owl/status/internal/builder.rb` — вторая копия резолв-ладдера.
- `lib/owl/tasks/internal/availability_scanner.rb` — авто-выбор/ранжирование.
- `lib/owl/tasks/api.rb` — `current`, `available`, `aggregate_status`.
- `lib/owl/workflows/backends/filesystem.rb` — `ready_steps`, `apply_children_gate`,
  определение терминального шага.
- `lib/owl/steps/internal/step_projection.rb`, `.../invocation_builder.rb` —
  `session_type`, `step_descriptor` (skill).
- `lib/owl/cli/internal/json_printer.rb` — `success/failure`, exit-коды.
- `lib/owl/version.rb`, `CHANGELOG.md`.
- `spec/owl/cli/instructions_spec.rb` — образец интеграционной CLI-специи + helpers.

# Checklist

- [ ] `lib/owl/orchestration/internal/next_action_resolver.rb` — новый
  `Owl::Orchestration::Internal::NextActionResolver.call(root:, task_id:, now:)`:
  резолв задачи (explicit → `Tasks::Api.current` → `Tasks::Api.available` верхний
  кандидат, без claim), затем классификация исхода в `action.kind`. Возвращает
  hash payload (`action`, `task_resolution`).
- [ ] Резолв ready/диспетч: внутри резолвера для резолвнутой задачи звать
  `Workflows::Api.ready_steps(task_id)`; на первом `ready`-шаге собрать
  `session_type` (`Steps::Internal::StepProjection.session_type`) и `skill`
  (`InvocationBuilder.step_descriptor`/как в `lookup_skill`) + резолвнутый `variant`.
- [ ] Классификация терминалов: `ready` пуст + `blocked_by_children` непуст →
  `handoff_composite` (+ `Tasks::Api.aggregate_status`); `ready` пуст + терминальный
  шаг workflow done → `done`; `ready` пуст + терминал не done + не дети →
  `stop_blocked` (+ `blocker`); нет задачи и `available` пуст → `no_available_task`.
- [ ] `task_resolution.needs_adopt`: выставлять `true`, когда у выбранной задачи
  истёк lease, но есть шаг в статусе `running` (определять через те же данные, что
  `AvailabilityScanner`/claim-чтение); саму задачу не мутировать.
- [ ] `lib/owl/orchestration/api.rb` — тонкий фасад
  `Owl::Orchestration::Api.next_action(root:, task_id: nil, now: Time.now)` →
  `Result::Ok(payload)`; инфраструктурные сбои (нет `.owl/`) → `Result::Err`.
- [ ] `lib/owl/orchestration.rb` (+ require в корневом `lib/owl.rb` или автозагрузке)
  — подключить новый домен по существующему паттерну загрузки доменов.
- [ ] `lib/owl/cli/internal/commands/next.rb` — `Owl::Cli::Internal::Commands::Next.run(argv:,stdout:,stderr:,cwd:,env:)`:
  парсит опциональный позиционный `TASK-ID` + `--root`, зовёт
  `resolve_root`/`Orchestration::Api.next_action`, печатает через `JsonPrinter.success`
  с `{ok:true, action:..., task_resolution:...}`; все `action.kind` → exit 0.
- [ ] `lib/owl/cli/api.rb` — зарегистрировать `'next' => Internal::Commands::Next`
  в `SIMPLE_COMMANDS` (топ-левел, рядом с `instructions`/`status`).
- [ ] Рефактор дублирующего резолв-ладдера: вынести общий «current → auto-select»
  helper (в `Orchestration::Internal` или `Tasks`), переиспользовать в
  `Instructions::Internal::PayloadBuilder` и `Status::Internal::Builder`; поведение
  существующих команд не меняется.
- [ ] `skills/owl-orchestrator/SKILL.md` — ужать прозу Workflow §1 (лестница) и §4
  (выбор шага) до «зови `owl next --json` и диспетчи по `action.kind`»; сохранить
  разделы про мутации (claim/adopt/heartbeat/steal/multi-session) как тонкую ссылку.
- [ ] `skills/owl-cli/SKILL.md` — добавить `owl next` в список команд + описание
  response shape (`action.kind`, `task_resolution`).
- [ ] Перематериализовать в этот репозиторий: после правки `skills/owl-*` выполнить
  `bin/owl upgrade` (или `bin/owl init --force`), чтобы `.claude/`/`.opencode/`
  отражали источник (специя `seeded_sources` это проверяет).
- [ ] `lib/owl/version.rb` — bump `Owl::VERSION` (minor — новая фича).
- [ ] `CHANGELOG.md` — запись о `owl next` под новой версией.
- [ ] `spec/owl/cli/next_spec.rb` — новая интеграционная специя (см. Tests).
- [ ] Если затронут любой `lib/owl/**/api.rb` — добавить/проверить юнит-специи на
  100% линий фасада.

# Tests and verification

- `spec/owl/cli/next_spec.rb` (новый), сценарии брифа:
  - auto-select при отсутствии указателя → `dispatch_step`, `source: auto_select`,
    без мутаций;
  - явный `TASK-ID` → `source: explicit`;
  - идемпотентность: два вызова подряд идентичны, состояние не изменилось;
  - `no_available_task` (пустой available, нет текущей) → exit 0;
  - `handoff_composite` для composite-родителя с `blocked_by_children`;
  - `done` при выполненном терминальном шаге;
  - `stop_blocked` при неудовлетворённой зависимости графа;
  - edge: `needs_adopt: true` при истёкшем lease + stuck `running`.
- Back-compat-гард: `spec/owl/cli/ready_steps_spec.rb`,
  `spec/owl/cli/task_available_spec.rb`, `instructions`/`status` специи — зелёные.
- `spec/owl/skills/seeded_sources_spec.rb` + `spec/owl/cli/init_skills_spec.rb` —
  зелёные после правки скиллов и `upgrade`.
- Прогон: `bundle exec rspec spec/owl/cli/next_spec.rb spec/owl/cli/ready_steps_spec.rb spec/owl/cli/task_available_spec.rb spec/owl/skills/seeded_sources_spec.rb`,
  затем полный `bundle exec rspec`. RuboCop по затронутым файлам.

# Smoke test

```
# В чистой текущей задаче TASK-0011 (есть ready-шаг):
bin/owl next --json
# Ожидаем: {"ok":true,"action":{"kind":"dispatch_step","task_id":"TASK-0011",
#           "step_id":"<next>","session_type":...,"skill":...},
#           "task_resolution":{"source":"current_pointer",...}}, exit 0

bin/owl next TASK-0011 --json   # source: explicit
bin/owl next --json; bin/owl next --json   # два вызова идентичны, состояние не менялось
```

# Out of scope

- Мутирующий режим `--act` (claim+start в одной команде) — отдельная будущая задача.
- Реальное выполнение `adopt`/`claim`/`step start` — остаётся отдельными вызовами
  оркестратора; `owl next` только сигналит `needs_adopt`.
- Изменение JSON-форм существующих команд (`available`/`ready-steps`/`instructions`/
  `step show`).
- Расширение множества `action.kind` сверх пяти значений.
