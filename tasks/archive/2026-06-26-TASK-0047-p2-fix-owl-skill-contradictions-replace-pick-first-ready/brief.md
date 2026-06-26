---
status: approved
summary: >-
  Устранить 4 противоречия в owl-* скиллах/командах: (1) убрать stale «pick first
  ready step» в пользу owl next; (2) минимизировать loop оркестратора (re-resolve
  через owl next, не ре-деривация); (3) дизамбигуировать перегруженный термин done;
  (4) поднять требование owl step reset для review_code changes_required в step-
  execution скилл. Только документация скиллов → patch bump + owl upgrade рефреш.
---

# Problem

Скиллы/команды оркестрации (`skills/owl-*`, `commands/owl-*`) накопили
внутренние противоречия — артефакт нескольких волн правок (трекер-слой,
`owl next`, session-typed шаги). Четыре конкретных:

1. **Stale «pick first ready step» против `owl next`.** Каноничный выбор
   шага — `owl next` (dispatch_step несёт `step_id`/`session_type`/`skill`),
   зафиксировано в `owl-orchestrator/SKILL.md` Workflow шаг 1 и Notes
   (стр. 96: «never pick the first entry… use owl next»). Но осталось
   противоречащее:
   - `skills/owl-orchestrator/SKILL.md:26` (Inputs): «otherwise pick the
     first entry from `owl task ready-steps`».
   - `commands/owl-task-next.md:7`: «take the first ready step».
   - `skills/owl-step-discussion/SKILL.md:70`: «take the requested or first
     ready entry».
2. **Loop оркестратора не минимален.** Workflow шаг 1 (`owl next`) уже
   возвращает `step_id`/`session_type`/`skill`, но шаги 2-5 повторно
   ре-деривят то же (status/instructions/step show), а «Loop from step 2»
   (стр. 60) предписывает ре-инспекцию каждой итерации вместо ре-резолва
   через `owl next` (шаг 1). Лишние шаги читаются как обязательные.
3. **Перегруженный термин `done`.** В прозе `done` означает минимум 4
   разных вещи: `owl next` `action.kind: done` (терминальный шаг завершён),
   статус шага `done`, статус задачи (terminal), и «терминальный шаг
   workflow завершён» (условие выхода из loop). Сливается, путает.
4. **`review_code` reset не поднят в step-execution.** Требование: при
   вердикте `changes_required` шаг `review_code` остаётся `running` и перед
   повторным прогоном нужен `owl step reset` — описано только в
   `owl-orchestrator/SKILL.md:59` и `owl-cli/SKILL.md:81`, но НЕ в
   `owl-step-execution` (где субагент реально ведёт review и оставляет шаг
   running). Оператор/ревьюер не видит требования там, где оно срабатывает.

Health-review-находка (label `health-review-2026-06-26`). `skills/**` и
`commands/**` — consumer-materialized seed (Конституция §7.1): расхождения
доезжают до consumer-проектов и сбивают агентов.

# Goal

Привести `owl-*` скиллы/команды к внутренней согласованности по четырём
пунктам, **хирургически** (точечные правки, без переписывания load-bearing
`owl-orchestrator/SKILL.md` целиком — риск регрессий в рабочем скилле):

1. Единый канон выбора: `owl next` (оркестратор) / явно переданный шаг
   (исполнители). Убрать формулировки «pick first ready step / first entry»
   как механизм выбора.
2. Минимальный, недвусмысленный loop оркестратора: ре-резолв через
   `owl next`; ре-инспекция (status/instructions/step show) явно помечена
   опциональной.
3. Дизамбигуация `done`: последовательные различимые термины для
   action-kind / step-status / task-status / terminal-step-complete.
4. Требование `owl step reset` для `review_code: changes_required` поднято
   в `owl-step-execution` (там, где review исполняется).

Изменение **только в документации скиллов/команд** (поведение CLI и кода
не трогаем). После правок — `bin/owl upgrade` для рефреша `.claude/`
(и `.opencode/` при наличии). По Конституции §7.1 `skills/**` в скоупе
версии → **patch bump** (доки-фикс, без изменения поведения) + `CHANGELOG`.

# Scenarios

### Requirement: единый канон выбора шага

The system SHALL NOT instruct the operator to select a workflow step by
taking the first entry of `owl task ready-steps`; the canonical selection
MUST be `owl next` (orchestrator) or an explicitly-passed step (executors).

#### Scenario: нет stale-формулировок выбора

- WHEN после правок выполнить grep по `skills/owl-*` и `commands/owl-*` на
  «first ready»/«first entry»/«pick … first» как механизм выбора
- THEN ни в одном orchestrator-уровневом месте такой формулировки нет
- AND `owl-orchestrator/SKILL.md` Inputs и `commands/owl-task-next.md`
  ссылаются на `owl next` как источник выбора

### Requirement: минимальный loop оркестратора

The system SHALL describe the orchestrator loop as re-resolving the next
action via `owl next` each iteration, with progress re-inspection marked
optional.

#### Scenario: loop ре-резолвит через owl next

- WHEN читать Workflow-секцию `owl-orchestrator/SKILL.md`
- THEN петля явно ре-резолвит через `owl next` (шаг 1), а не через
  ре-деривацию ладдера
- AND шаги ре-инспекции (status / instructions / step show) помечены
  опциональными

### Requirement: дизамбигуация термина done

The system SHALL use distinct, consistent wording for the four senses of
"done": `owl next` `action.kind: done`, step status `done`, task terminal
status, and "workflow terminal step complete".

#### Scenario: done различим по смыслу

- WHEN читать места употребления `done` в `owl-orchestrator/SKILL.md`
- THEN каждое употребление уточнено (напр. «action.kind `done`», «step
  status `done`», «terminal step complete») так, что смысл однозначен

### Requirement: review_code reset поднят в step-execution

The system SHALL state in `owl-step-execution` that a `review_code`
`changes_required` verdict leaves the step `running` and requires
`owl step reset` before a re-run.

#### Scenario: требование видно в исполнителе review

- WHEN читать `skills/owl-step-execution/SKILL.md`
- THEN присутствует явное указание: `changes_required` оставляет шаг
  `running`, повторный прогон требует `owl step reset TASK-ID review_code`

### Requirement: рефреш materialized-копий

The system SHALL refresh the materialized `.claude/` (and `.opencode/` if
present) copies after editing the source skills/commands.

#### Scenario: .claude рефрешнут

- WHEN после правок source `skills/owl-*`/`commands/owl-*` выполнить
  `bin/owl upgrade`
- THEN materialized `.claude/skills/owl-*` / `.claude/commands/owl-*`
  соответствуют источнику

# Edge cases

- **Не переписывать load-bearing скилл целиком.** `owl-orchestrator/SKILL.md`
  активно используется (в т.ч. этой сессией) — правки точечные, смысл
  существующих корректных секций сохраняется.
- **Исполнители vs оркестратор.** `owl-step-discussion`/`owl-step-execution`
  МОГУТ принимать явно переданный `STEP-ID` (его выбрал оркестратор через
  `owl next`) — это не противоречие; убрать надо именно «first ready entry»
  как *самостоятельный механизм выбора*, оставив «requested step».
- **`owl-cli` справочник.** `owl-cli/SKILL.md` описывает команды как
  reference — там `owl step reset` уже есть; дубль в step-execution
  оправдан (точка применения), не противоречие.
- **Версия.** Только доки скиллов → patch bump. Если правки заденут
  поведенческие формулировки контракта (не ожидается) — пересмотреть на
  minor.
- **`bin/owl upgrade` в этом репо** рефрешит `.claude/` от `skills/owl-*`;
  убедиться, что diff `.claude/` соответствует source-правкам и попадает в
  коммит.
- **Связь с другими health-review задачами** (0041/0048/0049) —
  ортогональны; здесь только доки скиллов.

# Acceptance criteria

- [ ] Нет orchestrator-уровневых формулировок «pick/take first ready
  step / first entry» как механизма выбора; `owl-orchestrator` Inputs и
  `commands/owl-task-next.md` ссылаются на `owl next`.
- [ ] Loop оркестратора описан как ре-резолв через `owl next`;
  ре-инспекция помечена опциональной.
- [ ] Все употребления `done` в `owl-orchestrator/SKILL.md` уточнены до
  однозначных (action.kind / step status / task status / terminal-step).
- [ ] `owl-step-execution/SKILL.md` содержит требование `owl step reset`
  для `review_code: changes_required`.
- [ ] `bin/owl upgrade` выполнен; `.claude/` (и `.opencode/` при наличии)
  синхронизированы с источником и в коммите.
- [ ] `Owl::VERSION` повышен по patch; запись в `CHANGELOG.md`.
- [ ] Изменения не трогают код `lib/owl/**` и поведение CLI (только доки).
