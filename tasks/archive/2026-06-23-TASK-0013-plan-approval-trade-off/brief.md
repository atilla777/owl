---
status: approved
summary: "Опциональный per-workflow гейт одобрения плана (выключен по умолчанию; состояние одобрения хранится в системе для headless/parallel) + фиксация автономии-по-умолчанию как осознанного trade-off в _owl_conventions.md."
---

# Brief: Опциональный plan-approval гейт + документирование автономии как trade-off

## Problem

Owl-оркестратор по умолчанию автономен после брифа
(`execution_mode: autonomous_after_brief`): пройдя `brief`, он сам ведёт
`design → plan → implement → … → commit_push` без пауз, останавливаясь лишь
на реальных блокерах. Это сознательное проектное решение, но:

- нет штатного способа объявить для рабочего процесса, что между `plan` и
  `implement` человек хочет одобрить план до написания кода (свериться с
  направлением для важных/рискованных процессов);
- сама автономия-по-умолчанию нигде явно не зафиксирована как осознанный
  trade-off — выглядит как умолчание без объяснения плюсов/минусов и без
  указания, как её при желании ужесточить.

Ключевой принцип пользователя: подтверждение не должно запрашиваться ради самой
операции. Гейт обязан быть опциональным и включаться только там, где человек
действительно хочет влиять на направление; сам момент одобрения — это настоящая
развилка (одобрить / запросить правки), а не формальный «да/нет».

## Goal

1. Дать возможность объявить в определении рабочего процесса (per-workflow, в
   YAML) опциональный гейт «одобрение плана»: при включённом гейте шаг
   `implement` не становится `ready`, пока план не одобрен.
2. По умолчанию (в seeded workflow `feature`/`composite_feature`/`hotfix`/
   `refactor`) гейт выключен — текущее автономное поведение не меняется;
   `owl upgrade` существующих проектов гейт не включает.
3. Сделать механику одобрения совместимой и с интерактивной, и с
   headless/параллельной работой: состояние «ждёт одобрения / одобрен» хранится
   в системе Owl (персистентно в состоянии задачи, через CLI), а не только в
   чате. Переиспользовать существующий в Owl механизм гейтов (`gate:`, как у
   композитных задач с `children_complete`).
4. Зафиксировать в `_owl_conventions.md` автономию-по-умолчанию как сознательный
   trade-off (плюсы/минусы) и описать, как включить опциональный гейт.

Решения, принятые на брифе (вход для шага `design`):
- **Гранулярность** — per-workflow (в YAML), не глобальный флаг и не per-task.
- **Механизм** — CLI как источник истины: новый `action.kind` в `owl next`
  (напр. `await_plan_approval`), команда одобрения (напр. `owl plan approve
  TASK-ID`), переиспользование инфраструктуры `gate:`. В живой сессии
  оркестратор показывает план и предлагает реальный выбор; решение фиксируется
  через CLI.
- **Документация trade-off** — в `_owl_conventions.md` (поведение оркестратора по
  чтению/уважению гейта — это реализация, а не «документация про trade-off»).

## Scenarios

### Requirement: Default autonomy is unchanged when the gate is off

The system SHALL drive a workflow without the plan-approval gate exactly as today, dispatching `implement` immediately after `plan` completes.

#### Scenario: Seeded feature workflow runs autonomously
- WHEN рабочий процесс задачи не объявляет plan-approval гейт (дефолт seeded `feature`)
- THEN после `step complete plan` шаг `implement` становится `ready` без какой-либо паузы на одобрение
- AND `owl next` возвращает `action.kind: dispatch_step` для `implement`
- TEST: spec/owl/specs/plan_approval_gate_spec.rb

### Requirement: An opt-in gate holds implement until the plan is approved

The system SHALL keep `implement` out of the ready set while the workflow declares the plan-approval gate and the plan is not yet approved.

#### Scenario: Gate blocks implement before approval
- WHEN рабочий процесс объявляет plan-approval гейт, а шаг `plan` завершён, но план не одобрен
- THEN `implement` не входит в `owl task ready-steps`
- AND `owl next` возвращает действие «ожидает одобрения плана» (новый `action.kind`), а не `dispatch_step`
- TEST: spec/owl/specs/plan_approval_gate_spec.rb

### Requirement: Plan approval is a persistent, CLI-driven state transition

The system SHALL record plan approval through a CLI command into persistent task state so the gate opens for any subsequent session, including headless and parallel ones.

#### Scenario: Approving the plan opens implement
- WHEN пользователь даёт одобрение плана командой owl (напр. `owl plan approve TASK-ID`)
- THEN состояние одобрения сохраняется в состоянии задачи
- AND после этого `implement` входит в `owl task ready-steps` и `owl next` возвращает для него `dispatch_step`
- TEST: spec/owl/specs/plan_approval_gate_spec.rb

#### Scenario: Approval is idempotent and lease-aware
- WHEN команда одобрения вызывается повторно для уже одобренного плана
- THEN команда завершается успешно (идемпотентно), не дублируя состояние
- AND мутация уважает claim/lease задачи так же, как прочие мутирующие команды
- TEST: spec/owl/specs/plan_approval_gate_spec.rb

### Requirement: Reopening the plan resets a prior approval

The system SHALL reset a recorded plan approval whenever the `plan` step is reopened, so stale plans cannot pass the gate.

#### Scenario: Reopen invalidates approval
- WHEN план был одобрен, после чего шаг `plan` переоткрыт (`owl step reopen`)
- THEN ранее записанное одобрение сбрасывается
- AND `implement` снова удерживается гейтом до нового одобрения
- TEST: spec/owl/specs/plan_approval_gate_spec.rb

### Requirement: The orchestrator presents a real choice in interactive sessions

The system SHALL, in an interactive session, present the plan and offer a genuine decision (approve / request changes) rather than a rubber-stamp confirmation, then record the outcome through the CLI.

#### Scenario: Interactive approval surfaces the plan
- WHEN оркестратор в живой сессии встречает действие «ожидает одобрения плана»
- THEN он показывает пользователю содержимое плана и предлагает выбор: одобрить или запросить правки
- AND при «одобрить» вызывает CLI-команду одобрения и продолжает с `implement`
- AND при «запросить правки» переоткрывает `plan` для доработки, оставляя гейт закрытым
- TEST: spec/owl/skills/owl_orchestrator_spec.rb

### Requirement: The autonomy trade-off is documented as a deliberate choice

The system SHALL document, in `_owl_conventions.md`, the default autonomy as a conscious trade-off and explain how to enable the optional plan-approval gate.

#### Scenario: Conventions describe trade-off and opt-in
- WHEN читатель открывает `_owl_conventions.md`
- THEN там есть раздел, объясняющий автономию-по-умолчанию как осознанный trade-off (плюсы и минусы)
- AND там описано, как объявить опциональный plan-approval гейт в рабочем процессе
- TEST: spec/owl/docs/conventions_plan_approval_spec.rb

## Edge cases

- **Гейт включён, но в рабочем процессе нет шага `plan` или `implement`** —
  конфигурационная ошибка; валидация определения рабочего процесса должна это
  отклонять с понятным структурированным кодом ошибки.
- **Back-compat схемы рабочего процесса** — новое поле гейта опционально;
  существующие YAML без него остаются валидными и ведут себя как раньше.
- **Параллельные сессии** — одобрение — мутация, уважает claim/lease; две сессии
  не могут гонять одобрение одной задачи одновременно.
- **Идемпотентность** — повторное `approve` безопасно; `approve` без завершённого
  `plan` отклоняется понятной ошибкой.
- **Композитные задачи** — гейт `plan_approval` независим от существующего
  `children_complete`; они не должны конфликтовать в движке готовности.
- **Апгрейд проектов** — `owl upgrade` не включает гейт в уже установленных
  seeded workflow (поведение по умолчанию сохраняется).

## Acceptance criteria

- В YAML рабочего процесса можно объявить опциональный plan-approval гейт; seeded
  workflow его не включают, дефолтное автономное поведение не меняется.
- При включённом гейте `implement` не запускается до одобрения плана; это видно в
  `owl task ready-steps` и `owl next` (новый `action.kind`/блокер) и работает в
  headless.
- Есть CLI-команда одобрения плана; состояние одобрения персистентно в состоянии
  задачи, идемпотентно, уважает claim/lease.
- `owl step reopen plan` сбрасывает одобрение.
- Оркестратор (`owl-orchestrator` SKILL) в интерактивной сессии показывает план и
  предлагает реальный выбор (одобрить / запросить правки), а не формальное
  «да/нет».
- `_owl_conventions.md` содержит раздел: автономия-по-умолчанию как осознанный
  trade-off (плюсы/минусы) + как включить опциональный гейт.
- Соблюдены правила проекта: bump `Owl::VERSION` + запись в `CHANGELOG.md`
  (затронуты `lib/**`, `bin/owl`, `skills/**`, `workflows/**`, `schemas/**`);
  100% покрытие строк для новых/изменённых `lib/owl/**/api.rb`; доступ к
  `.owl/`/`tasks/`/`docs/` только через слои Owl; конституция соблюдена.
- Тесты покрывают: гейт держит `implement`, `approve` открывает, `reopen`
  сбрасывает, идемпотентность/уважение lease, back-compat рабочего процесса без
  гейта, отклонение мисконфигурации.
