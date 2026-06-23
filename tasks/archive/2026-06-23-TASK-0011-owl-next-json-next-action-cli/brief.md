---
status: approved
summary: Вынести next-action оркестратора (резолв задачи + выбор шага + диспетч + терминалы) из прозы скилла owl-orchestrator в read-only команду `owl next --json` с дискриминированным action.kind, оставив существующие CLI-контракты back-compatible и ужав прозу лестницы в скиллах до вызова новой команды.
---

# Problem

Решение «что оркестратору делать дальше» сейчас живёт **прозой** в скилле
`owl-orchestrator` (лестница выбора задачи в Workflow §1, выбор ready-шага §4,
диспетч по `session_type` §6, обработка терминалов/handoff §8–9). Эта логика:

- **не в коде** — её нельзя покрыть тестами; единственная гарантия корректности —
  что агент правильно прочитает несколько экранов текста;
- **дрейфует** — проза и фактическое поведение CLI расходятся (тот же класс
  проблемы, что push-lock drift в коммите 8e1613b);
- **дублируется и переинтерпретируется** — каждый агент/сессия заново выводит
  «лестницу» из текста, результат недетерминирован;
- **толстая** — основной объём скилла именно про выбор следующего действия.

Нужен единый авторитетный источник правды для next-action — в коде, а не в прозе.

# Goal

Добавить read-only команду `owl next --json`, которая инкапсулирует полное
решение «что делать дальше»: резолвит задачу по канонической лестнице, выбирает
следующий ready-шаг с диспетч-информацией, а в тупиковых случаях возвращает
терминальный исход. Скилл `owl-orchestrator` (и упоминания лестницы в `owl-cli`)
ужимаются до вызова `owl next` + интерпретации одного `action.kind`. Существующие
команды (`task available`, `ready-steps`, `instructions`, `step show`) и их
JSON-контракты остаются неизменными (back-compat).

Не в скоупе: само исполнение действия (`claim`/`adopt`/`step start`) — команда
только советует, мутации остаются отдельными вызовами оркестратора.

# Scenarios

### Requirement: Команда отдаёт следующее действие одним вызовом

The system SHALL предоставлять команду `owl next --json`, которая резолвит
задачу по канонической лестнице (явный TASK-ID → текущий указатель → авто-выбор
через `task available`) и возвращает следующий ready-шаг с диспетч-информацией.

#### Scenario: Авто-выбор при отсутствии текущего указателя
- WHEN текущего указателя нет и есть ≥1 runnable-задача в `task available`
- THEN `owl next --json` возвращает `action.kind: "dispatch_step"` с верхней по
  приоритету задачей, её следующим ready-шагом, `session_type` и `skill`
- AND `task_resolution.source` равен `"auto_select"` с объяснимым `reason`
- AND команда не мутирует состояние (claim не берётся)
- TEST: spec/owl/cli/next_spec.rb

#### Scenario: Явный TASK-ID имеет приоритет
- WHEN вызывается `owl next TASK-0011 --json` при заданном другом текущем указателе
- THEN возвращается next-action для TASK-0011, а `task_resolution.source` равен `"explicit"`
- TEST: spec/owl/cli/next_spec.rb

### Requirement: Команда не мутирует состояние

The system SHALL быть идемпотентной и read-only — `owl next` не берёт claim, не
стартует шаги и не пишет в `.owl/`/`tasks/`.

#### Scenario: Повторный вызов не меняет состояние
- WHEN `owl next --json` вызывается дважды подряд на одном репозитории
- THEN оба вызова возвращают идентичный результат
- AND ни один claim/lease/step-status не изменился между вызовами
- TEST: spec/owl/cli/next_spec.rb

### Requirement: Терминальные исходы выражены через action.kind

The system SHALL кодировать тупиковые и переходные исходы единым
дискриминированным полем `action.kind` из фиксированного множества
{`dispatch_step`, `handoff_composite`, `stop_blocked`, `done`, `no_available_task`}.

#### Scenario: Нет runnable-задач
- WHEN `task available` пуст и нет текущей задачи с ready-шагами
- THEN `owl next --json` возвращает `action.kind: "no_available_task"` (а не сырую ошибку `no_current_task`)
- AND exit code равен 0 (это валидный исход, не ошибка)
- TEST: spec/owl/cli/next_spec.rb

#### Scenario: Composite-родитель ждёт детей
- WHEN текущая задача — composite-родитель, чьи оставшиеся шаги `blocked_by_children`
- THEN `owl next --json` возвращает `action.kind: "handoff_composite"` с aggregate-статусом детей
- TEST: spec/owl/cli/next_spec.rb

#### Scenario: Терминальный шаг выполнен
- WHEN у текущей задачи `ready-steps` пуст и терминальный шаг workflow выполнен
- THEN `owl next --json` возвращает `action.kind: "done"`
- TEST: spec/owl/cli/next_spec.rb

#### Scenario: Граф заблокирован неудовлетворённой зависимостью
- WHEN `ready-steps` пуст, терминальный шаг НЕ выполнен и это не ожидание детей
- THEN `owl next --json` возвращает `action.kind: "stop_blocked"` с описанием блокера
- TEST: spec/owl/cli/next_spec.rb

### Requirement: Существующие CLI-контракты сохраняются

The system SHALL оставить JSON-контракты команд `task available`, `ready-steps`,
`instructions` и `step show` неизменными — `owl next` композирует их, а не
заменяет.

#### Scenario: Старые команды не меняют форму ответа
- WHEN после внедрения `owl next` вызываются `owl task available --json` и `owl task ready-steps --json`
- THEN их JSON-формы идентичны прежним (существующие специи остаются зелёными)
- TEST: spec/owl/cli/ready_steps_spec.rb
- TEST: spec/owl/cli/task_available_spec.rb

### Requirement: Проза лестницы в скиллах заменяется ссылкой на команду

The system SHALL ужать прозу селекшн-лестницы и выбора шага в `skills/owl-orchestrator`
(и упоминания в `skills/owl-cli`) до вызова `owl next` и интерпретации `action.kind`,
устранив дублирующий источник правды.

#### Scenario: Скилл делегирует решение CLI
- WHEN читается обновлённый `skills/owl-orchestrator/SKILL.md`
- THEN Workflow-шаг выбора следующего действия инструктирует звать `owl next --json` и диспетчить по `action.kind`
- AND правка `skills/**` сопровождается bump `Owl::VERSION` и записью в `CHANGELOG.md`
- TEST: spec/owl/skills/seeded_sources_spec.rb

# Edge cases

- **Истёкший lease при stuck `running`-шаге.** `owl next` должен сообщать о
  необходимости `adopt` (например, через `action.kind: "stop_blocked"` или
  отдельный признак в `task_resolution`), но сам adopt не выполняет — мутация
  остаётся за оркестратором.
- **`lease_held` другой живой сессией.** Авто-выбор пропускает задачи с живым
  claim чужой сессии (как `task available`); это не ошибка `owl next`.
- **Несколько одинаково-приоритетных задач.** Тай-брейк по возрасту, как в
  `task available`; результат детерминирован.
- **Параллельные сессии.** Поскольку команда read-only, одновременные вызовы из
  разных сессий безопасны и не создают гонок.
- **Вариант шага (`variants`).** `dispatch_step` отдаёт дефолтный/резолвнутый
  вариант так же, как `ready-steps`/`step show`; выбор не-дефолтного варианта
  остаётся явным действием оркестратора (`step start --variant`).
- **Будущий `--act`.** Возможный режим, выполняющий claim+start, сознательно
  вынесен в отдельную задачу и в этом скоупе не реализуется.

# Acceptance criteria

- `owl next --json` существует, документирован в выводе `owl --help`/`owl-cli`
  скилле и возвращает стабильный JSON с полем `action.kind` из фиксированного
  множества {`dispatch_step`, `handoff_composite`, `stop_blocked`, `done`,
  `no_available_task`}.
- Команда **read-only**: не берёт claim, не стартует шаги, не пишет в `.owl/`
  или `tasks/`; повторный вызов идемпотентен.
- Резолв задачи следует канонической лестнице (явный TASK-ID → текущий указатель
  → авто-выбор), с объяснимым `task_resolution.source`/`reason`.
- Терминальные исходы (`no_available_task`, `done`, `stop_blocked`,
  `handoff_composite`) возвращаются с exit code 0 как валидные действия, а не как
  сырые ошибки.
- JSON-контракты `task available`, `ready-steps`, `instructions`, `step show`
  не изменены; их существующие специи остаются зелёными.
- `skills/owl-orchestrator` (и упоминания в `skills/owl-cli`) ужаты до вызова
  `owl next` + диспетча по `action.kind`; дублирующая проза лестницы удалена.
- Все новые/затронутые пути покрыты RSpec; для `lib/owl/**/api.rb`, если затронут,
  держится 100% линий (per `docs/agents/30_*`).
- Правка `skills/**` (и кода) сопровождается bump `Owl::VERSION` (minor — новая
  фича) и записью в `CHANGELOG.md` в том же коммите (per Constitution §7.1).
