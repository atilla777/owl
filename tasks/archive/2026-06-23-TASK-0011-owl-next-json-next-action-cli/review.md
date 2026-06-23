---
status: resolved
summary: Реализация `owl next` (домен Owl::Orchestration) полностью покрывает брифовые критерии — read-only, идемпотентна, фиксированное множество action.kind, exit 0 на всех терминалах, корректная лестница резолва и сигнал needs_adopt; back-compat сохранён, версия 0.2.0 + CHANGELOG, скиллы перематериализованы. Добавлено недостающее покрытие резолва variant; блокеров нет.
verdict: accepted
ready: true
---

# Summary

Ревью охватывает рабочее дерево TASK-0011: новый домен `Owl::Orchestration`
(`Api.next_action`, `Internal::NextActionResolver`, `Internal::TaskResolver`),
команду `owl next [TASK-ID] --json`, дедуп резолв-ладдера через
`Tasks::Api.current_task_id`, ужатую прозу скиллов `owl-orchestrator`/`owl-cli`
(+ перематериализация `.claude/`), bump `Owl::VERSION 0.1.1 → 0.2.0` и запись в
`CHANGELOG.md`.

Реализация соответствует брифу и дизайну. Проверено не чтением, а прогоном:
`spec/owl/cli/next_spec.rb` (11 примеров, 0 падений), back-compat-гарды
`instructions`/`status`/`task_commands`/`lease_commands` + skills-гарды
`seeded_sources`/`init_skills` (129 примеров, 0 падений), полный
`bundle exec rspec` (1630 примеров, 0 падений, 1 pending), RuboCop по всем
изменённым файлам — без замечаний. Дымовые `owl next TASK-0011 --json` и
`owl --help` корректны.

Все семь блоков acceptance-критериев брифа выполнены:

- **Read-only / идемпотентность** — резолвер композирует только читающие API
  (`current`, `available`, `ready_steps`, `inspect`, `claims`,
  `aggregate_status`); claim/start/записи нет. Тест проверяет реально: после
  вызова `task current` возвращает не-ноль (указатель не записан), `claims`
  пуст, два последовательных вызова дают идентичный JSON.
- **Фиксированное множество `action.kind`** ∈ {dispatch_step,
  handoff_composite, stop_blocked, done, no_available_task}, каждый объект
  `action` несёт полный набор ключей (`null` для неприменимых) —
  подтверждено дымовым выводом.
- **Все терминалы exit 0**, сырой `no_current_task` не протекает — маппится в
  `no_available_task` (source `none`).
- **Лестница резолва** explicit → current_pointer → auto_select корректна;
  `task_resolution.source/reason` объяснимы. Покрыто тремя тестами.
- **needs_adopt** выставляется строго при stuck `running`-шаге + присутствующем
  истёкшем lease; покрыт edge-тестом.
- **Back-compat** `task available`/`ready-steps`/`instructions`/`step show` —
  JSON-формы не тронуты, их гарды зелёные; рефактор `current_task_id`
  поведенчески нейтрален (на success отдаёт unwrapped `task_id`, на err — тот же
  `Err`, как раньше).
- **Constitution §7.1** — minor-bump 0.2.0 + CHANGELOG в дереве, `.claude/`
  перематериализован (seeded_sources зелёный).

# Findings

### F1 — Незакрытое покрытие резолва `variant` (severity: minor) — ИСПРАВЛЕНО

`NextActionResolver#resolve_variant` для `dispatch_step` имеет ветку «выбран
`default_variant`/task-chosen variant», но ни один сид в `next_spec.rb` не
объявлял `variants`, поэтому метод всегда возвращал `nil` на первом гварде —
резолвнутая ветка не исполнялась. Бриф прямо называет вариант-диспетч edge-кейсом
(«`dispatch_step` отдаёт дефолтный/резолвнутый вариант, как `ready-steps`/`step
show`»), так что это реальный пробел в проверке, а не косметика.

**Resolution:** добавлен `describe 'variant resolution on dispatch_step'` с двумя
тестами (workflow-сид со `default_variant: feature` + `variants:`):
default-вариант отдаётся, когда задача его не выбирала, и task-chosen
(`--variant brief=root_cause`) перекрывает дефолт. Оба зелёные — ветка
`resolve_variant` теперь покрыта end-to-end.

### F2 — `done` классифицируется по «все шаги done/skipped», а не «терминальный шаг done» (severity: info)

Дизайн формулирует `done` как «терминальный шаг workflow выполнен»; реализация
использует `all_steps_done?` (все шаги в done/skipped). В ветвящихся workflow это
**строже** дизайна: если параллельная ветка не завершена при готовом терминале,
вернётся `stop_blocked`, а не `done` — что корректнее (задача реально не
закончена). Расхождение безопасно и в нужную сторону; оставлено как есть.
Зафиксировано для памяти при будущем расширении.

### F3 — `auto_select` маскирует инфра-ошибку `available` в `no_available_task` (severity: info)

`TaskResolver.auto_select` берёт `top` только когда `available.ok?`; при
`Err` (например, повреждённый индекс) `top` станет `nil` → `no_available_task`.
Инфраструктурный сбой `available` редок и сам по себе сигнализируется в других
путях; для read-only советчика деградация в «нет задач» приемлема. Не блокер.

### F4 — `needs_adopt?` дублирует вычисление истечения lease (severity: info)

`claim_entry` уже несёт булев `:expired` (через `ExclusiveLease.expired?`), а
резолвер заново парсит `expires_at` своим `lease_expired?`. Дублирование
оправдано тем, что резолвер пробрасывает инъектируемый `now` (которого нет у
`claims`), что делает edge-тест детерминированным. Поведение согласовано; чистка
не требуется.

# Resolution

Единственная правка ревью — закрытие пробела покрытия F1 (тесты, не продакшн-код;
поведение не менялось). F2–F4 — информационные наблюдения без действий:
осознанные, безопасные компромиссы, согласованные с дизайном и residual-risks
верификации. Продакшн-логика домена `Orchestration`, дедуп `current_task_id` и
ужатие скиллов приняты без изменений.

Контрольный прогон после правки: `next_spec` 11/0, полный `rspec` 1630/0/1pending,
RuboCop по изменённым файлам и новой специи — 0 замечаний; `orchestration/api.rb`
и `tasks/api.rb` отсутствуют в списке «ниже 100% линий» (оба фасада на 100%).

# Remediation

- `spec/owl/cli/next_spec.rb` — добавлен `describe 'variant resolution on
  dispatch_step'` (2 теста), покрывающий резолвнутый `variant` в `dispatch_step`.

# Residual risks

- `action.kind` и форма `{ok, action, task_resolution}` стали публичным
  контрактом — расширять только аддитивно (новый kind = minor; удаление/
  переименование/смена формы = major, Constitution §7.1).
- `needs_adopt` намеренно не срабатывает на `running`-шаге без lease (нормальный
  одно-сессионный in-flight) — это by design, держать в уме при будущем
  расширении на multi-session сценарии.
- Распространение 0.2.0 в consumer-проекты (re/Rrrog, tetris) требует отдельного
  релиз-шага (gem rebuild + per-project `owl upgrade`) — вне скоупа этого шага.
