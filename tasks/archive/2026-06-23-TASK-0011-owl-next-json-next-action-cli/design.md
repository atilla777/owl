---
status: approved
summary: Новая read-only команда верхнего уровня `owl next` через отдельный домен `Owl::Orchestration`, чей `NextActionResolver` композирует существующие Tasks/Workflows/Instructions API (резолв задачи → ready-steps → диспетч → классификация терминала) и возвращает дискриминированный `action.kind`; существующие CLI-контракты не трогаются.
---

# Context

Решение «что оркестратору делать дальше» (бриф TASK-0011) сейчас живёт прозой в
`skills/owl-orchestrator`. Нужно вынести его в код как read-only `owl next --json`.

Карта существующего кода (из разведки):

- **Слоистость** (`docs/agents/27_*`): `Owl::<Domain>::Api` — публичный фасад,
  возвращает `Result::Ok/Err`, без бизнес-логики; `Internal::*` — сервис-классы;
  `Backends::*` — пуггабл-бэкенды (FS).
- **Резолв задачи уже есть в коде** (но дублируется): `Instructions::Internal::PayloadBuilder.call`
  и `Status::Internal::Builder.call` оба реализуют «explicit task_id → current
  pointer (`Tasks::Api.current`) → иначе `:no_current_task`». Авто-выбора там нет.
- **Авто-выбор**: `Tasks::Internal::AvailabilityScanner.scan(root:, now:)` —
  ранжирование `[-priority, created_at, task_id]`, исключает живые claim'ы и
  gated composite-родителей, возвращает `{available:[{task_id,title,kind,priority,
  created_at,ready_step_ids,reason}]}`.
- **Ready-steps + терминалы**: `Workflows::Backends::Filesystem.ready_steps(task_id:)`
  → `{ready:[...], blocked_by_children:[...]}`; `apply_children_gate` уводит
  gated-шаги в `blocked_by_children`.
- **Диспетч-инфо**: `Steps::Internal::StepProjection.session_type(step)` (дефолт
  `execution`) и `InvocationBuilder.step_descriptor(step)` (поле `skill`);
  `Instructions::Internal::PayloadBuilder.lookup_skill` читает skill + `SkillReader`.
- **CLI**: реестр `Owl::Cli::Api` — `SIMPLE_COMMANDS` (топ-левел: `instructions`,
  `status`) и `TASK_SUBCOMMANDS` (`available`, `ready-steps`...). Каждая команда —
  модуль `Internal::Commands::<Name>.run(argv:,stdout:,stderr:,cwd:,env:)`.
- **JSON**: `Cli::Internal::JsonPrinter.success/failure`; ошибки `{ok:false,
  error:{code,message,error_class,details}}`, exit-коды validation=1/recoverable=2/
  fatal=3.
- **Специи CLI**: `spec/owl/cli/<subject>_spec.rb`, интеграционные, зовут
  `Owl::Cli::Api.run` напрямую, helper'ы `with_tmp_project`, `run(argv,cwd:)`.

Вся логика для next-action **уже существует разрозненно** — задача в композиции и
классификации, а не в новой бизнес-логике.

# Decision

1. **Новый домен `Owl::Orchestration`** с публичным `Api.next_action(root:,
   task_id: nil, now:)`. Внутри — `Internal::NextActionResolver`, который
   **композирует существующие API**, ничего не реимплементируя и ничего не мутируя.
2. **Команда верхнего уровня `owl next`** (не `owl task next`) — регистрируется в
   `SIMPLE_COMMANDS` рядом с `instructions`/`status`, т.к. она может резолвить
   задачу через лестницу, а не привязана к одной. Опциональный позиционный
   `TASK-ID`, флаг `--json` (как у прочих). Модуль
   `Cli::Internal::Commands::Next.run`.
3. **Алгоритм `NextActionResolver`** (read-only):
   1. *Резолв задачи*: explicit `task_id` → `Tasks::Api.current` (текущий
      указатель) → `Tasks::Api.available` (верхний кандидат). Фиксируем
      `task_resolution.source ∈ {explicit, current_pointer, auto_select}` и
      `reason`. **Claim не берётся.**
   2. Если задача не резолвится и `available` пуст → `action.kind:
      "no_available_task"`.
   3. Иначе считаем `Workflows::Api.ready_steps(task_id)`:
      - `ready` непуст → `dispatch_step` с первым шагом + `session_type` + `skill`
        (через `StepProjection`/`step_descriptor`, как `instructions`);
      - `ready` пуст, есть `blocked_by_children` → `handoff_composite` +
        `Tasks::Api.aggregate_status`;
      - `ready` пуст, терминальный шаг workflow выполнен → `done`;
      - `ready` пуст, терминал не выполнен, не ожидание детей → `stop_blocked` с
        описанием блокера.
   4. Признак `task_resolution.needs_adopt: true` (без мутации), когда у
      кандидата истёк lease, но шаг застрял `running` — оркестратор сам решает
      `adopt`.
4. **Контракт `action.kind`** — фиксированное множество `{dispatch_step,
   handoff_composite, stop_blocked, done, no_available_task}`. Все исходы — exit
   code **0** (валидные действия, не ошибки). Сырой `no_current_task` наружу не
   протекает.
5. **Back-compat**: `task available`, `ready-steps`, `instructions`, `step show`
   и их JSON не трогаем — `owl next` только читает их доменные API.
6. **Дедуп прозы**: дублирующий резолв-ладдер в `PayloadBuilder`/`Builder`
   рефакторим на общий `Orchestration` (или общий helper), чтобы не плодить
   третью копию лестницы; прозу лестницы в `skills/owl-orchestrator` ужимаем до
   «зови `owl next` и диспетчи по `action.kind`», в `skills/owl-cli` добавляем
   запись о команде. Это правка `skills/**` + кода → bump `Owl::VERSION` (minor) +
   `CHANGELOG.md`.

# Alternatives

- **A. Оставить логику в прозе скилла (статус-кво).** Отклонено: это сама
  проблема брифа — нет тестируемости, есть дрейф.
- **B. Расширить `owl instructions` полем `action.kind`.** Отклонено: ломает
  семантику существующего task-scoped контракта (нарушает back-compat-овёрлей
  брифа), `instructions` не делает авто-выбор задачи и не классифицирует терминалы.
- **C. Положить резолвер в `Tasks::Api.next`.** Отклонено: next-action пересекает
  три домена (Tasks-резолв + Workflows-граф + Steps-диспетч + Instructions-skill);
  домен Tasks не должен владеть workflow-графом и skill-биндингом — это нарушит
  слоистость `27_*`. Выделенный домен `Orchestration` держит границы чистыми.
- **D. Сделать команду мутирующей (`--act`: claim+start).** Отклонено в этом
  скоупе (решение брифа): команда «вычисли действие» обязана быть идемпотентной и
  безопасной для параллельных сессий; `--act` вынесен в отдельную будущую задачу.
- **E. `owl task next` (под task-деревом) вместо топ-левел.** Отклонено:
  команда не привязана к одной задаче (делает авто-выбор), поэтому топ-левел
  рядом с `status`/`instructions` семантически точнее; плюс брифовые примеры —
  `owl next` / `owl next TASK-0011`.

# Risks

- **Дрейф классификации vs реальная readiness-машина.** Митигируется композицией
  существующих API (`ready_steps`, `aggregate_status`), а не копией графовой
  логики. Специя `next_spec.rb` сверяет исходы с прямыми вызовами `ready-steps`.
- **`action.kind` становится публичным контрактом.** Фиксируем множество как
  стабильное, расширяемое только аддитивно (новый kind = minor, удаление/
  переименование = major per Constitution §7.1). Документируется в `owl-cli`.
- **Мисклассификация `stop_blocked` vs `handoff_composite`.** Разводим строго по
  наличию `blocked_by_children` в ответе `ready_steps`; покрываем обоими
  сценариями брифа.
- **Stale lease + stuck `running`.** Сообщаем `needs_adopt` без мутации; если
  забыть — оркестратор не узнает, что нужен `adopt`. Покрывается edge-специей.
- **Рефактор дублирующего резолва (`PayloadBuilder`/`Builder`).** Риск регрессий
  в `instructions`/`status`. Митигируется: их существующие специи остаются
  зелёными как контракт-гард; рефактор — поведенчески нейтральный.
- **Потеря нюансов при ужатии прозы скилла** (steal/adopt/heartbeat/multi-session).
  Не удаляем эти разделы целиком — оставляем тонкую ссылку; из прозы уходит только
  дублирующая лестница выбора, мутации и их предостережения остаются.
- **Покрытие `api.rb`.** Если резолвер вынесен за `Api` (в `Internal`), `api.rb`
  остаётся тонким фасадом — 100%-линий-гейт `30_*` достижим тривиально.

# API

Новый домен (публичная поверхность, публикуется в `docs/` через `merge_docs`):

```ruby
# lib/owl/orchestration/api.rb
module Owl
  module Orchestration
    module Api
      # Read-only. Не берёт claim, не стартует шаги, не пишет в .owl/ или tasks/.
      # task_id: nil → лестница (current pointer → auto-select).
      # Возвращает Result::Ok(payload) | Result::Err(...). Доменные ошибки
      # маппятся в action.kind, а не в Err (кроме инфраструктурных, напр. нет .owl).
      def self.next_action(root:, task_id: nil, now: Time.now); end
    end
  end
end
```

CLI:

```
owl next [TASK-ID] [--json] [--root PATH]
```

JSON-ответ (стабильный контракт):

```jsonc
{
  "ok": true,
  "action": {
    "kind": "dispatch_step",              // ∈ {dispatch_step, handoff_composite,
                                          //    stop_blocked, done, no_available_task}
    "task_id": "TASK-0011",
    "step_id": "design",                  // только для dispatch_step
    "session_type": "discussion",         // только для dispatch_step
    "skill": "owl-step-discussion",       // только для dispatch_step
    "variant": null,                       // резолвнутый вариант, если объявлен
    "blocker": null,                       // строка-описание для stop_blocked
    "children": null                       // aggregate-status для handoff_composite
  },
  "task_resolution": {
    "source": "auto_select",              // ∈ {explicit, current_pointer, auto_select, none}
    "reason": "highest-priority runnable task",
    "needs_adopt": false                   // true: истёкший lease + stuck running
  }
}
```

Семантика `action.kind` (все — exit code 0):

| kind | Когда | Доп. поля |
| --- | --- | --- |
| `dispatch_step` | резолвнут шаг к запуску | `task_id, step_id, session_type, skill, variant` |
| `handoff_composite` | composite-родитель ждёт детей | `task_id, children` |
| `done` | ready пуст, терминальный шаг выполнен | `task_id` |
| `stop_blocked` | ready пуст, граф заблокирован | `task_id, blocker` |
| `no_available_task` | нет резолвимой задачи и `available` пуст | — |

Внутреннее устройство:

- `lib/owl/orchestration/internal/next_action_resolver.rb` —
  `NextActionResolver.call(root:, task_id:, now:)`; композирует
  `Tasks::Api.current/available`, `Workflows::Api.ready_steps`,
  `Tasks::Api.aggregate_status`, `Steps::Internal::StepProjection`,
  `InvocationBuilder.step_descriptor`.
- `lib/owl/cli/internal/commands/next.rb` — `Next.run`, регистрируется в
  `Cli::Api::SIMPLE_COMMANDS['next']`.
- Рефактор: общий резолв-ладдер (current→auto) переиспользуется
  `Instructions`/`Status` вместо третьей копии.

Затронутые/новые тесты:

- `spec/owl/cli/next_spec.rb` (новый) — все сценарии брифа + edge (needs_adopt).
- `spec/owl/skills/seeded_sources_spec.rb` — обновлённый текст
  `skills/owl-orchestrator`.
- `spec/owl/cli/ready_steps_spec.rb`, `spec/owl/cli/task_available_spec.rb`,
  `instructions`/`status` специи — остаются зелёными (back-compat-гард).
