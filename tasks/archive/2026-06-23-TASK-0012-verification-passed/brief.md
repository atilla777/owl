---
status: approved
summary: Объективный verification-гейт — Owl сам прогоняет настроенную тест-команду в шаге review_code, по exit code выставляет verification.status и блокирует завершение шага при не-passed; fail-open без команды.
---

## Problem

Сейчас «верификация» в Owl — это самоотчёт агента. Шаг `implement` создаёт
артефакт `verification` с frontmatter `status: passed|failed|partial`, который
агент-исполнитель **пишет сам**. Owl ничего не запускает и не проверяет exit
code: агент может написать `status: passed`, не прогнав тесты (или прогнав не
все), и граф рабочего процесса спокойно пропустит задачу дальше.

Граф тоже не гейтит по результату верификации. Готовность вычисляется только по
*завершённости* предыдущего шага: как только `implement` помечен `done`, шаг
`review_code` становится `ready` — даже если бы `status` был `failed`.
Единственный существующий гейт графа — `gate: children_complete` для composite —
к качеству кода отношения не имеет.

Итог: «green verification» в Owl сегодня — необъективный сигнал, на который
нельзя опереться как на контроль качества поставки.

## Goal

Сделать verification-гейт **объективным** и **встроенным в граф**:

1. Финальный авторитетный прогон тестов выполняет **сам Owl** (подпроцесс,
   exit code), а не агент — подделать результат нельзя.
2. Этот прогон и гейт живут в шаге **`review_code`** (фаза проверки качества).
   `implement` остаётся «строительным» шагом: итеративные прогоны агента по ходу
   написания — его внутренняя кухня и не гейтятся.
3. Завершение `review_code` **блокируется**, пока объективный `status` не
   `passed`. Провал отбрасывает работу назад в `implement` (reopen с каскадом).
4. Поведение **opt-in** и обратно совместимо: пока verify-команда не настроена,
   гейт выключен (fail-open + warning), существующие консьюмеры (re/Rrrog,
   tetris) не ломаются на `owl upgrade`.

## Scenarios

### Requirement: Owl objectively runs the configured verification command

The system SHALL execute the configured verification command itself as a
subprocess and derive `verification.status` from its exit code, instead of
trusting an agent-authored status.

#### Scenario: Configured command exits zero
- WHEN `settings.verification.command` задана в `.owl/config.yaml` и Owl
  запускает объективный прогон в шаге `review_code`
- AND команда завершается с exit code 0
- THEN Owl сам записывает `status: passed` в `verification.md`
- AND сохраняет фактически выполненную команду и хвост её вывода в артефакте
- TEST: spec/owl/verification/run_command_spec.rb

#### Scenario: Configured command exits non-zero
- WHEN настроенная verify-команда завершается с ненулевым exit code
- THEN Owl записывает `status: failed` с этим прогоном
- AND статус выставлен Owl, а не агентом (агент не может его переопределить)
- TEST: spec/owl/verification/run_command_spec.rb

### Requirement: review_code completion is gated on an objective passed verification

The system SHALL refuse to complete the `review_code` step while the objective
`verification.status` is not `passed`, when a verification command is configured.

#### Scenario: Completing review_code with failed verification
- WHEN verify-команда настроена и объективный `status` равен `failed`
- THEN `owl step complete TASK-ID review_code` отклоняется со структурированной
  ошибкой и ненулевым exit code
- AND граф не продвигается: `merge_docs` остаётся не-ready
- TEST: spec/owl/cli/step_complete_verification_gate_spec.rb

#### Scenario: Completing review_code with passed verification
- WHEN verify-команда настроена и объективный `status` равен `passed`
- THEN `owl step complete TASK-ID review_code` проходит
- AND `merge_docs` становится `ready`
- TEST: spec/owl/cli/step_complete_verification_gate_spec.rb

### Requirement: A failed objective verification can send work back to implement

The system SHALL allow a failed verification at `review_code` to reopen the
`implement` step together with the steps that transitively require it.

#### Scenario: Reopen implement after a failed review verification
- WHEN объективный прогон в `review_code` дал `failed`
- AND человек/оркестратор выполняет `owl step reopen TASK-ID implement --cascade`
- THEN `implement` и зависящие от него шаги (`review_code`, далее) переходят в
  `pending`
- AND после исправления кода цикл implement → review повторяется
- TEST: spec/owl/cli/step_reopen_cascade_spec.rb

### Requirement: The verification command is configured per project

The system SHALL read the verification command from
`settings.verification.command` in `.owl/config.yaml`, not from a managed
workflow or artifact definition.

#### Scenario: Command read from project config
- WHEN проект задаёт `settings.verification.command: "bundle exec rspec"`
- THEN объективный прогон в `review_code` исполняет именно эту команду
- AND seeded `workflows/feature/workflow.yaml` не содержит хардкода команды
  (managed-определения кастомизируются клонированием, а не правкой)
- TEST: spec/owl/config/verification_command_spec.rb

### Requirement: The gate is opt-in and fails open when unconfigured

The system SHALL leave the verification gate inactive (allow progression with a
warning) when no verification command is configured, preserving current
behaviour for existing consumers.

#### Scenario: No command configured
- WHEN `settings.verification.command` не задана
- THEN Owl не запускает прогон, гейт не блокирует `review_code`
- AND печатает warning о неактивном гейте
- AND `owl upgrade` в существующем проекте без команды не меняет его поведение
- TEST: spec/owl/cli/step_complete_verification_gate_spec.rb

#### Scenario: Partial status does not block
- WHEN объективный/отчётный `status` равен `partial`
- THEN завершение `review_code` разрешено с warning, а не блокируется
- TEST: spec/owl/cli/step_complete_verification_gate_spec.rb

## Edge cases

- **Свежесть результата.** Нужно защититься от «прогнал зелёное → поправил код →
  закрыл шаг». Owl уже считает `content_sha` артефактов и предупреждает о дрейфе;
  объективный verify-результат должен быть привязан к состоянию дерева/артефакта
  и считаться устаревшим, если код менялся после прогона. Точный механизм — за
  шагом `design`.
- **Артефакт-владелец статуса.** Где именно фиксируется объективный `status` —
  в существующем `verification` (сейчас `creates:` у `implement`) или в `review`
  — решается на `design`. Сегодня `implement` создаёт `verification`; перенос
  авторства/гейта в `review_code` затрагивает workflow.yaml.
- **Долгие/зависшие тесты.** Прогон может превысить TTL claim'а — нужен heartbeat
  и/или таймаут команды; поведение по таймауту = `failed`. Детали — `design`.
- **Падение самой команды (не тестов).** Команда не найдена / ошибка окружения
  отличается от «тесты упали»: трактовать как блокирующую ошибку запуска с
  понятным сообщением, не как тихий `passed`.
- **Многосессионность.** Объективный прогон в `review_code` исполняется под
  per-task step-lock'ом; это не вводит репозиторно-широкой сериализации.
- **Конституция/обратная совместимость.** Изменение поведения и seeded-контента
  требует бампа `Owl::VERSION` + запись в `CHANGELOG.md` в том же коммите
  (Constitution §7.1). Новое поле `settings.verification.*` должно пройти
  валидацию схемы конфига.

## Acceptance criteria

- При заданной `settings.verification.command` Owl сам исполняет её в шаге
  `review_code`, по exit code выставляет `verification.status` (агент не может
  переопределить), и сохраняет команду + хвост вывода в артефакте.
- При не-`passed` объективном статусе `owl step complete TASK-ID review_code`
  отклоняется со структурированной ошибкой и ненулевым exit code; `merge_docs`
  не становится ready.
- При `passed` — `review_code` завершается и граф продвигается.
- `owl step reopen TASK-ID implement --cascade` корректно отбрасывает работу в
  `implement` после провала верификации.
- Команда читается только из `.owl/config.yaml`
  (`settings.verification.command`); в seeded workflow.yaml команды нет.
- Без настроенной команды гейт неактивен (fail-open + warning); `partial` не
  блокирует; `owl upgrade` не меняет поведение проектов без команды.
- Покрытие: новые/изменённые публичные методы `lib/owl/**/api.rb` имеют 100%
  построчного покрытия (см. docs/agents/30); названы конкретные spec-файлы.
- `Owl::VERSION` поднят (minor — новая фича) и добавлена запись в `CHANGELOG.md`
  в том же коммите.
