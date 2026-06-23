---
status: approved
summary: "Plan-approval — это новый per-step gate (gate: plan_approved), обобщающий существующий механизм gate на не-composite задачи; одобрение — персистентное task-level состояние, выставляемое командой owl plan approve и сбрасываемое при reopen plan; owl next получает action.kind await_plan_approval."
---

# Design: Опциональный plan-approval гейт

## Context

Текущая механика (по карте кода):

- **Готовность шагов.** `Owl::Workflows::Internal::ReadyResolver.resolve`
  (`lib/owl/workflows/internal/ready_resolver.rb:12`) считает «сырой» ready-set:
  шаг `pending` + все `requires` завершены.
- **Гейты.** `Owl::Workflows::Backends::Filesystem#ready_steps`
  (`lib/owl/workflows/backends/filesystem.rb:295`) поверх сырого набора
  применяет `apply_children_gate` (там же, :341). Сейчас гейт **один**
  (`GATE_CHILDREN_COMPLETE = 'children_complete'`) и применяется **только для
  composite-задач** (`kind == composite_task`). Результат —
  `{ ready, blocked_by_children }`.
- **Решение «что дальше».** `Owl::Orchestration::Internal::NextActionResolver#classify`
  (`lib/owl/orchestration/internal/next_action_resolver.rb:56`) превращает
  ready-set в `action.kind`: `dispatch_step` / `handoff_composite` (когда пусто,
  но есть `blocked_by_children`) / `done` / `stop_blocked` / `no_available_task`.
  Поля действия берутся из стабильного `ACTION_FIELDS` (там же, :23), где уже
  есть `step_id`.
- **Состояние шагов** хранится в `tasks/<ID>/task.yaml` (`steps[].status`).
  `Owl::Steps::Api.reopen` (`lib/owl/steps/api.rb:132`) переводит `done → pending`.
- **Схема workflow** — `schemas/workflow.json` (step def :33, `additionalProperties:
  true`), валидируется `Owl::Workflows::Internal::WorkflowValidator` через
  `SchemaCheck.walk` (:35). Новое опциональное поле back-compat по построению.
- **CLI** — диспетчер `Owl::Cli::Api#dispatch_command`
  (`lib/owl/cli/api.rb:116`); группы команд — тонкие адаптеры к доменным
  `Owl::<Domain>::Api`, возвращающим `Result::Ok/Err`.
- **Конвенции** — источник истины `skills/_owl_conventions.md`
  (материализуется в `.claude/skills/` через `owl init/upgrade`).

Бриф зафиксировал решения: гейт **per-workflow** (в YAML), состояние одобрения
**в системе** (для headless/parallel), документирование trade-off в
`_owl_conventions.md`. Открытые архитектурные вопросы, которые закрывает этот
дизайн: (1) как обобщить gate на обычные задачи; (2) где и как хранить факт
одобрения и когда его сбрасывать; (3) форма CLI и нового `action.kind`.

## Decision

**1. Гейт — новое значение существующего поля `gate`: `plan_approved`.**
Объявляется на шаге (обычно `implement`): `gate: plan_approved`. Это переиспользует
уже существующий словарь `gate`, а не вводит новое поле. В `schemas/workflow.json`
у step-свойства `gate` фиксируем `enum: ["children_complete", "plan_approved"]`
(поле опциональное → существующие workflow валидны без изменений). Seeded workflow
(`feature`/`composite_feature`/`hotfix`/`refactor`) гейт **не** объявляют —
дефолтная автономия не меняется; `owl upgrade` его не добавляет.

**2. Обобщить применение gate на любые задачи.** В
`Filesystem#ready_steps` ввести второй фильтр `apply_plan_approval_gate`,
работающий **независимо от `kind`** (не только composite). Он удерживает шаги с
`gate: plan_approved` из `ready`, пока task-level состояние одобрения не
выставлено, и складывает их в **новый** ключ результата
`awaiting_plan_approval` (аддитивно к `ready`/`blocked_by_children` — контракт
JSON не ломается). `children_complete` остаётся как есть.

**3. Одобрение — персистентное task-level состояние.** В `task.yaml` вводим
top-level ключ `plan_approval` (вложенный объект, не голый bool — расширяемо):

```yaml
plan_approval:
  approved: true
  plan_sha: <content_sha артефакта plan на момент одобрения>
  approved_at: <ts>
```

Гейт открыт, когда `plan_approval.approved == true` **и** `plan_sha` совпадает с
текущим `content_sha` артефакта `plan`. Привязка к `plan_sha` делает сброс при
переписывании плана автоматическим и устойчивым; явный сброс при `reopen plan`
(см. 4) даёт второй, наблюдаемый барьер. (Шаг `plan` уже в `requires`
`implement`, поэтому отдельной проверки «plan done» гейту не нужно.)

**4. Сброс одобрения.** `Owl::Steps::Api.reopen` при переоткрытии шага `plan`
(в т.ч. каскадно) очищает `plan_approval`. Это прямо реализует AC «reopen plan
сбрасывает одобрение» и не зависит от sha-эвристики.

**5. CLI и доменный API.** Новая группа команд `owl plan`:
- `owl plan approve TASK-ID` — выставляет `plan_approval`. Мутация **lease-aware**
  тем же механизмом, что прочие task-мутации (отвергается, если задачу держит
  другая живая сессия). Идемпотентна (повторный вызов на одобренном с тем же
  `plan_sha` — `ok`, без дублирования).
- `owl plan status TASK-ID` — read-only: одобрено ли, какой `plan_sha`, открыт ли
  гейт (удобно оркестратору/headless без разбора `task inspect`).

Реализация — фасад `Owl::Tasks::Api.approve_plan` / `.plan_status`
(домен Tasks владеет task-level состоянием и claim/lease) +
`Owl::Tasks::Internal::PlanApproval`. CLI: `Owl::Cli::Internal::Commands::PlanApprove`
/ `PlanStatus`, ветка `when 'plan' then dispatch_plan` в `dispatch_command`.
Перед `approve` валидируется, что `plan` завершён (иначе `Err(plan_not_completed)`).

**6. `owl next` → новый `action.kind: await_plan_approval`.** В `classify`
после ветки `blocked_by_children` добавить: если `awaiting_plan_approval.any?` →
`action('await_plan_approval', task_id:, step_id: <удержанный шаг>, blocker:
<человекочитаемое>)`. Новых полей в `ACTION_FIELDS` не требуется (`step_id`,
`blocker` уже есть).

**7. Оркестратор (skill).** `owl-orchestrator/SKILL.md`: при
`action.kind: await_plan_approval` в живой сессии показать содержимое артефакта
`plan` и предложить **реальный выбор** (одобрить → `owl plan approve`; запросить
правки → `owl step reopen plan` и доработать) — не формальный штамп. В
headless — это стоп-точка, ожидающая внешнего `owl plan approve`. Документировать
поведение и сам trade-off автономии в `skills/_owl_conventions.md` (новый раздел).

**8. Валидация конфигурации.** `WorkflowValidator`: если шаг объявляет
`gate: plan_approved`, но в workflow нет шага `plan` (или нет шага-носителя
гейта) — структурированная ошибка (`gate_requires_plan`). `children_complete` вне
composite-workflow — оставить текущее поведение (гейт просто не срабатывает) во
избежание регрессий.

## Alternatives

1. **Глобальный флаг в `.owl/config.yaml` (отвергнут на брифе).** Один
   `settings.orchestration.plan_approval`. Проще, но не per-workflow и хуже
   ложится на существующую инфраструктуру `gate`. Пользователь выбрал
   per-workflow.

2. **`execution_mode: interactive_after_plan` на уровне workflow вместо
   per-step `gate`.** Семантически чисто, но `execution_mode` сегодня читается
   skill-ами для решения «спрашивать ли пользователя», а не движком готовности —
   пришлось бы учить readiness-движок новому источнику истины. `gate` уже **в**
   движке готовности → меньше нового кода и один механизм вместо двух. Отвергнут
   в пользу `gate: plan_approved`.

3. **Хранить одобрение как псевдо-шаг `plan_approval` в графе** (шаг, который
   «выполняет» человек). Переиспользовал бы `step complete`, но засоряет граф
   workflow искусственным шагом, ломает диаграммы и `requires`-логику, и плохо
   выражает идемпотентность/сброс. Отвергнут.

4. **Только sha-привязка без поля `approved` / без reopen-хука.** Гейт открыт,
   если существует запись `plan_sha == current`. Минимально, но AC явно требует
   «reopen plan сбрасывает одобрение» как наблюдаемое поведение, а голый sha не
   даёт чистого `plan status`. Берём гибрид (поле + sha + reopen-хук).

5. **Только интерактивный промпт без CLI-состояния (отвергнут на брифе).** Не
   работает в headless/parallel — противоречит принципу Owl «состояние в
   системе».

6. **Reset одобрения по таймеру/TTL.** Лишняя сложность; одобрение логически
   действительно до изменения плана. Отвергнут.

## Risks

- **Регрессия дефолтной автономии.** Если фильтр применится к задачам без
  `gate: plan_approved`, сломается весь автопоток. Митигировать: гейт активен
  строго при наличии `gate: plan_approved` у шага; тест «seeded feature идёт
  автономно» (есть в брифе как Scenario) — обязательный.
- **Контракт JSON `ready-steps`/`next`.** Добавляем ключ `awaiting_plan_approval`
  и `action.kind`. Аддитивно, но потребители, делающие строгий разбор, должны
  игнорировать незнакомые kind — это уже требование оркестратора. Бамп —
  **minor** (фича), не breaking.
- **Гонки параллельных сессий.** `approve` без lease-проверки мог бы открыть
  гейт из чужой сессии. Митигировать: та же lease-модель, что у прочих
  task-мутаций; тест на idempotency + lease.
- **Композитные задачи.** `plan_approved` и `children_complete` могут оказаться
  на разных шагах одного workflow. Фильтры независимы; нужен тест, что они не
  затирают buckets друг друга.
- **Stale sha.** Если plan переоткрыт и завершён байт-в-байт идентично, sha
  совпадёт и одобрение формально «переживёт» — но reopen-хук всё равно его
  очистит, так что наблюдаемое поведение корректно.
- **100% покрытие `api.rb`.** Новые публичные методы `Tasks::Api.approve_plan` /
  `.plan_status` требуют полного построчного покрытия (constitution §) — заложить
  специи на все ветки (ok, plan_not_completed, lease-conflict, idempotent).

## API

Публичная поверхность, публикуемая в `docs/` при `merge_docs`:

**Новые CLI-команды**

- `owl plan approve TASK-ID [--token TOKEN]` → `{ ok, task_id, plan_approval: {
  approved, plan_sha, approved_at } }`. Ошибки: `plan_not_completed`,
  `lease_held`, `unknown_task`.
- `owl plan status TASK-ID` → `{ ok, task_id, approved, plan_sha, gate_open }`.

**Изменения существующих контрактов**

- `owl task ready-steps TASK-ID --json` / `Owl::Workflows::Api.ready_steps`:
  добавлен ключ `awaiting_plan_approval: [step_id, …]` (рядом с `ready`,
  `blocked_by_children`).
- `owl next` / `Owl::Orchestration::Api.next_action`: новый
  `action.kind: "await_plan_approval"` с заполненными `task_id`, `step_id`,
  `blocker` (прочие поля `ACTION_FIELDS` — `null`).
- `owl step reopen TASK-ID plan`: побочный эффект — очистка `plan_approval`.

**Схема workflow** (`schemas/workflow.json`)

- step-свойство `gate`: `enum: ["children_complete", "plan_approved"]`
  (опциональное; отсутствие = нет гейта).

**Состояние задачи** (`task.yaml`, через слои Owl, не править руками)

- top-level `plan_approval: { approved: bool, plan_sha: string, approved_at:
  string }` (отсутствует, пока не одобрено).

**Доменный API (Ruby)**

- `Owl::Tasks::Api.approve_plan(root:, task_id:, token: nil) -> Result`
- `Owl::Tasks::Api.plan_status(root:, task_id:) -> Result`
- `Owl::Steps::Api.reopen(...)` — расширен сбросом `plan_approval` при reopen
  шага `plan`.
