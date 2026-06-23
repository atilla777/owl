---
status: approved
summary: "Verification-гейт как step-marker verify:true (по образцу publishes:true); Owl запускает settings.verification.command в Owl::Steps::Api.complete, объективно перезаписывает verification.md и блокирует завершение при не-passed. Свежесть — by-construction (прогон в момент complete). Standalone owl verify."
---

## Context

Точки интеграции в коде (проверено по дереву):

- **`Owl::Steps::Api.complete`** (`lib/owl/steps/api.rb:67`) — единственная точка
  завершения шага: проверяет `running` → `OutputValidator.call` →
  `ArtifactShaCollector` → `StatusWriter`. Сюда встраивается гейт.
- **`publishes: true`-маркер** (`lib/owl/publish/internal/step_gate.rb`) —
  каноничный прецедент: шаг *опт-инит* поведение булевым полем, id шага
  резолвится из workflow, а не хардкодится. Verification-гейт следует ровно этому
  образцу полем `verify: true`.
- **`gate: children_complete`** (`lib/owl/workflows/backends/filesystem.rb:341`)
  — гейт *готовности* (держит шаг вне ready-steps). Наш гейт — гейт *завершения*,
  это другая семантика, поэтому переиспользовать поле `gate` нельзя.
- **Config-валидатор** (`lib/owl/config/internal/validator.rb`) — `validate_settings`
  уже валидирует `language` / `storage` / `agent_targets`; добавляется
  `validate_settings_verification`.
- **Subprocess** — `Open3.capture3` (см. `lib/owl/upgrade/internal/shell_runner.rb`).
- **Step-поля workflow** (`lib/owl/workflows/internal/step_lookup.rb:7`) — список
  распознаваемых строковых/булевых полей шага; сюда добавляется `verify`.

Решения brief, которые design конкретизирует: (1) объективный прогон делает Owl;
(2) гейт на завершении `review_code`; (3) команда из config; (4) fail-open.
Открытые из brief вопросы (свежесть, артефакт-владелец, таймаут) закрываются ниже.

## Decision

**1. Объявление гейта — step-marker `verify: true`.** В YAML рабочего процесса шаг
опт-инит гейт полем `verify: true` (по образцу `publishes: true`). Seeded
workflow'ы `feature`/`hotfix`/`refactor` получают `verify: true` на шаге
`review_code`. `composite_feature` — нет (его `review` валидирует декомпозицию,
а не код). Команда в YAML **не** хранится.

**2. Движок — `Owl::Verification`.** Новый домен `lib/owl/verification/` (Backend/
Internal/Api по архитектуре docs/agents/27). `Api.run` исполняет
`settings.verification.command` через `Open3.capture3` с таймаутом, ловит exit
code и **сам** перезаписывает `verification.md`:

- frontmatter `status`: `0` → `passed`; ненулевой → `failed`; таймаут → `failed`
  (+ `partial_reason: timeout`);
- `## Commands` — фактическая команда; `## Outcomes` — exit code и хвост вывода
  (последние N строк stdout+stderr, обрезка по размеру);
- `## Failures or blockers` — хвост при провале, иначе `None`.

Агент не участвует в записи статуса — отсюда «объективность».

**3. Точка и механика гейта — `Owl::Steps::Api.complete`.** После
`OutputValidator.call`, если у завершаемого шага `verify: true`:

- команда **не** настроена → fail-open: warning в stderr, завершение проходит
  (гейт неактивен);
- команда настроена → `Owl::Verification::Api.run` (прогон + перезапись
  `verification.md`) → если итоговый `status != passed` (т.е. `failed`; `partial`
  пропускается с warning) → `Result.err(code: :verification_failed)` (exit≠0),
  шаг остаётся `running`; иначе завершение проходит штатно.

**4. Свежесть — by-construction.** Прогон происходит *в момент* `complete` против
текущего дерева, поэтому окно устаревания отсутствует и отдельный
tree-fingerprint не нужен. Это закрывает edge-case brief'а без новой машинерии.

**5. Владелец артефакта — `review_code`.** `creates: [verification]` переносится с
`implement` на `review_code`; `verification.md` становится Owl-авторским
(пишется движком на гейте). `implement` остаётся build-шагом и не создаёт
артефактов (как `merge_docs`/`archive`). Обновляются `implement.context.md`
(убрать авторство verification) и `review_code.context.md` (объективный гейт).

**6. Standalone `owl verify TASK-ID [--json]`.** Тот же движок, доступен вручную/
агенту для пред-проверки без завершения шага. Возвращает
`{ok, status, exit_code, command, gate_active}`.

**7. Reopen-петля.** Провал на `review_code` чинится существующим
`owl step reopen TASK-ID implement --cascade` — новой машинерии не требуется,
только покрытие тестом.

**8. Конфиг.** `settings.verification.command` (string|null, дефолт отсутствует),
`settings.verification.timeout_seconds` (integer, дефолт 1800). Валидируются
`validate_settings_verification`.

## Alternatives

- **Гейт по самоотчётному frontmatter агента (без прогона Owl).** Отклонено в
  brief: тот же self-report, не объективно.
- **Прогон в `owl step complete` vs отдельный `owl verify` + freshness-fingerprint.**
  Рассмотрен вариант: агент зовёт `owl verify`, пишет результат + sha дерева,
  `complete` сверяет свежесть. Отклонён: вводит окно устаревания и
  fingerprint-машинерию. Прогон-на-complete свеж by-construction. `owl verify`
  оставлен лишь как удобный pre-check, не как источник гейта.
- **Оставить авторство `verification` на `implement`, перештамповывать на review.**
  Меньше churn в YAML/контекстах, но два актора пишут один артефакт и версия
  агента выбрасывается — концептуально мутно. Выбран чистый перенос авторства на
  `review_code`.
- **Переиспользовать поле `gate` (`gate: verification`).** Отклонено: `gate` —
  гейт *готовности* (ready-resolver), наш — гейт *завершения*; смешение семантик
  усложнит обе ветки. Отдельное булево `verify:` яснее.
- **Команда в workflow.yaml на шаге.** Отклонено в brief: managed-определения
  кастомизируются клонированием; стек — свойство проекта, ему место в config.
- **Отдельный новый шаг `verify` между implement и review_code.** Отклонено:
  добавляет узел графа и ещё одну subagent-сессию; brief свёл гейт в `review_code`.

## Risks

- **Долгий прогон превышает claim TTL.** `complete` синхронно гоняет весь сьют;
  при длинном прогоне lease (дефолт 600s) может истечь и задачу уведут.
  Смягчение: таймаут команды по умолчанию 1800s, оркестратор обязан
  `owl task heartbeat`/`--ttl` перед завершением verify-шага; зафиксировать в
  `review_code.context.md` и в overlay оркестратора. Полноценное решение
  (heartbeat внутри прогона) — возможный follow-up.
- **Ошибка запуска команды vs провал тестов.** exit 127 / команда не найдена —
  это `run_error`, не «тесты упали». Трактуем оба как блок, но с разными
  сообщениями/`partial_reason`, чтобы не выдать тихий `passed` и не спутать
  диагностику.
- **Обратная совместимость.** Маркер `verify: true` появляется в seeded
  workflow'ах; на `owl upgrade` он попадёт к консьюмерам без команды → fail-open
  (гейт молчит). Поведение проектов без `settings.verification.command` не
  меняется — инвариант проверяется тестом.
- **Покрытие публичного API.** `lib/owl/verification/api.rb` и затронутый
  `lib/owl/steps/api.rb` требуют 100% построчного покрытия (docs/agents/30) —
  движок должен принимать инъектируемый runner, чтобы специи гоняли гейт без
  реального сьюта.
- **Перенос `creates: [verification]`.** Меняет seeded YAML и context-файлы →
  затрагивает upgrade существующих задач в полёте; снизить риск, ограничив
  изменение определением workflow (новые задачи), не трогая live task.yaml.
- **Версионирование.** Изменение поведения + seeded-контента → bump
  `Owl::VERSION` (minor) + `CHANGELOG.md` в том же коммите (Constitution §7.1).

## API

**Config (`settings.verification`, schema_version 1):**

```yaml
settings:
  verification:
    command: "bundle exec rspec"   # string|null; нет → гейт неактивен (fail-open)
    timeout_seconds: 1800          # integer; дефолт 1800
```

Валидация (`validate_settings_verification`): `command` — непустая строка или
отсутствует; `timeout_seconds` — положительный integer или отсутствует.
Коды ошибок: `invalid_settings_verification_shape`,
`invalid_settings_verification_command`, `invalid_settings_verification_timeout`.

**Ruby (`Owl::Verification::Api`):**

```
run(root:, task_id:, command: nil, timeout: nil, runner: default_runner)
  → Result.ok(status:, exit_code:, command:, output_tail:, duration:, timed_out:)
  # исполняет команду, перезаписывает tasks/<id>/verification.md,
  # status ∈ {passed, failed}; runner инъектируется для тестов.
  → Result.err(code: :verification_command_missing)   # когда command отсутствует и явно запрошен
```

**Workflow-схема (`schemas/workflow.json`, `step_lookup`):** новое булево поле
шага `verify` (дефолт `false`). Резолвер id-шага с гейтом — по образцу
`Publish::Internal::StepGate.resolve_step_id` (первый шаг с `verify: true`).

**CLI:**

- `owl verify TASK-ID [--json]` → `{ok, status, exit_code, command, gate_active}`;
  `gate_active:false` + warning, когда команда не настроена.
- `owl step complete TASK-ID review_code` — при `verify: true`:
  - команда настроена и `status != passed` → структурированная ошибка
    `verification_failed` (exit≠0), детали `{status, exit_code, command}`, шаг
    остаётся `running`;
  - команда не настроена → warning `verification_gate_inactive`, завершение
    проходит;
  - `status == passed` → штатное завершение.

Публикуемая в `docs/` поверхность (через `merge_docs`): обновлённый
`docs/agents/`-раздел про verification-гейт и `settings.verification.*` — точный
файл определит `merge_docs` по `publishes:`-правилам.
