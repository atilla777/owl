---
number: 1
title: Session-typed steps and subagent contract
status: Accepted
authors:
  - Owl maintainers
created: 2026-05-24
slug: architecture_sessions_rfc
knowledge_entry_id: 46
---

# RFC #1 — Session-typed steps and subagent contract

> **Abstract.** Owl architecture RFC. Адресует две структурные дыры, выявленные в TD-139 retrospective (tetris/snake): (1) orchestrator живёт в одном непрерывном контексте без первоклассного различия между discussion и execution фазами; (2) скиллы написаны Claude-Code-specific, без environment-agnostic abstraction, что блокирует Codex/OpenCode. RFC закрепляет: `session_type` (discussion/execution), 2 model tier (standard/advanced), env-agnostic `spawn_subagent` контракт, CLI `owl step report`, breaking-switch миграция, явный verdict эксперимента с AskUserQuestion из subagent.

## 1. Контекст и мотивация

RFC — первый child задачи TD-139 (Container, retrospective "Owl improvements from tetris/snake"), Блок А. Retrospective сформулировал Q1–Q15 принятых ранее решений; данный RFC не пересматривает Q1–Q15, а консолидирует их в архитектурное полотно и закрывает оставшиеся ambiguity.

Source-of-truth: Owl Constitution (article 23, `load_policy: required`). RFC опирается на §2 (иерархия source-of-truth), §3 (workflow-политика) и §4 (качественные ворота) Constitution.

Ключевая структурная гипотеза: текущая монолитная orchestrator-сессия плохо масштабируется по двум осям одновременно — стоимость токенов (long discussion) и качество исполнения (high-tier model для коротких execution-блоков). Решение — разделить session_type'ы и tier'ы; параллельно вынести Claude-Code-specifics в overlay поверх env-agnostic ядра.

## 2. Session types

**Implementation anchors.** Constants in `lib/owl/steps/internal/step_projection.rb:14` (`SESSION_TYPES = %w[discussion execution]`) and `:16` (`DEFAULT_SESSION_TYPE = 'execution'`); the `session_type(step)` projector lives at `lib/owl/steps/internal/step_projection.rb:49-59`. Workflow schema validates `session_type` in `lib/owl/workflows/internal/workflow_validator.rb:140` (error message points back to this RFC §2).

`session_type` — атрибут логической сессии работы агента, известный orchestrator до её спавна. Минимум 2 значения, каждое со строго заданными свойствами:

| Свойство | `discussion` | `execution` |
|---|---|---|
| Назначение | Долгое обсуждение, brainstorming, спецификация, дизайн-выбор | Короткая фокусированная мутация: code change, artifact write, verification |
| Default model tier (см. §3) | `advanced` | `standard` |
| History retention | Накапливает полный контекст разговора; orchestrator-уровень | Изолированная сессия, контекст ограничен входным пакетом; cleared after report |
| Output contract | Свободный диалог + опциональный structured artifact | Обязательный structured report (markdown-with-frontmatter, см. §4.3) |
| Human-interaction | Может задавать вопросы человеку напрямую (main-session-only механизмы — например AskUserQuestion в Claude Code) | НЕ может; вместо этого пишет report и завершается |
| Live skill loading | Полный load `live_skills:retrieve` для текущего workflow_status | Тот же набор, что был получен orchestrator'ом перед спавном (передаётся в input пакете) |

Расширяемость: будущие значения (`research`, `documentation`, и т. д.) появляются как формальное расширение enum; orchestrator должен явно знать дефолты для tier и output contract по каждому добавляемому значению.

Decision: **`discussion` всегда выполняется в main agent session** (не в subagent). Это закрывает ambiguity спецификации: subagent имеет тип `execution`, исключения нет.

## 3. Model tiers

**Implementation anchors.** Constants `MODEL_TIERS = %w[standard advanced]` and `DEFAULT_MODEL_TIER = 'standard'` live in `lib/owl/steps/internal/step_projection.rb:15,17`; the projector method is at `:68-78`. Workflow validator at `lib/owl/workflows/internal/workflow_validator.rb:151` references this RFC §3. Per-environment mapping example: `docs/examples/tier_map.example.yaml`.

RFC закрепляет ровно **два** tier: `standard` и `advanced`.

| Tier | Когда применяется | Что важно |
|---|---|---|
| `standard` | Default для `execution`-сессий: imports, refactors, артефактные writes, scripted verification, format-only edits | Дешёвый, быстрый. Не предназначен для дизайн-выбора |
| `advanced` | Default для `discussion`-сессий и любых ситуаций, где execution требует не-тривиального reasoning (например debug сложной concurrency, миграция данных, security review) | Дороже, тщательнее. Используется selectively |

Tier'ы — это **семантическое имя**, не имя конкретной модели. Mapping `tier → model` живёт в **env-specific конфиге уровня окружения**:

- Owl-репо хранит абстракцию tier (`standard`/`advanced`).
- Конкретная привязка (`standard = claude-sonnet-4-6`, `advanced = claude-opus-4-7`) — в файле уровня окружения, не уровня скилла. Пример пути: `~/.config/owl/tier_map.yaml` или env-variable `OWL_TIER_MAP_PATH`, конкретный формат закрепляет TD-141.
- Скилл/workflow YAML обязан ссылаться только на tier-имя; прямые упоминания модели в скилле — нарушение env-agnostic правила.
- Конкретные имена моделей (Claude / GPT / Gemini / open-weights) RFC намеренно не закрепляет: список меняется быстрее RFC.

Decision: **mapping per-environment, не per-project и не per-skill.** Per-project mapping не нужен (один dev / один env), per-skill mapping приведёт к фрагментации.

## 4. spawn_subagent contract

Контракт `spawn_subagent` — env-agnostic. Любая runtime-обёртка (Claude Code, Codex, OpenCode, или будущая) обязана реализовать его в семантически эквивалентной форме. В тексте контракта нет упоминаний конкретных tool API.

### 4.1 Inputs

| Поле | Тип | Семантика |
|---|---|---|
| `session_type` | enum (`discussion`/`execution`/…) | Обязательно. Orchestrator выбирает на основании текущей stage и task контекста. |
| `tier` | enum (`standard`/`advanced`) | Обязательно. Default = default tier для session_type, может быть override'нут orchestrator'ом. |
| `intent` | string (markdown) | Обязательно. Human-readable формулировка цели сессии. |
| `context_pack` | object | Обязательно. Структурированный bundle с минимумом: задача (id/title/body), workflow status, нужные artifact references, retrieval-bundle (knowledge articles), allow-list разрешённых tool'ов. |
| `output_spec` | object | Обязательно. Описывает формат отчёта: список required-секций, формат frontmatter, разрешённые статусы. |
| `budget` | object | Опционально. Лимиты времени / токенов / tool-вызовов. |
| `secrets_redactor` | object | Опционально. Список ключей/паттернов, которые subagent НЕ должен встретить и не должен возвращать. |

### 4.2 Outputs (то, что main session получает обратно)

| Поле | Тип | Семантика |
|---|---|---|
| `final_state` | enum (`returned_normally`/`interrupted`/`error`/`budget_exceeded`) | Обязательно. Жёстко проверяется orchestrator'ом. |
| `report_body` | string (markdown-with-frontmatter, см. §4.3) | Обязательно при `final_state=returned_normally`. |
| `report_artifacts` | array | Опционально. Ссылки на созданные/обновлённые KOS-артефакты (для аудита). |
| `tool_usage_summary` | array | Опционально. Сжатая выкладка о tool-вызовах внутри сессии (для аудита и telemetry). |
| `error_message` | string | При `final_state=error/interrupted/budget_exceeded`. |

### 4.3 Отчётный формат (report_body)

**Implementation anchors.** The validator for this format lives in `lib/owl/subagents/internal/output_spec.rb:10-28` (module `OutputSpec` with constants `ALLOWED_STATUSES`, `DEFAULT_REQUIRED_FRONTMATTER_KEYS`, `DEFAULT_REQUIRED_SECTIONS`). Filesystem persistence: `lib/owl/subagents/internal/filesystem_report_backend.rb:14`.

Решение: **markdown-with-frontmatter**, единый формат для всех session_type'ов.

Обоснование: KOS-artifact body уже использует markdown+frontmatter (artifact_requirements). Использование того же формата для отчёта sub-сессии даёт три преимущества:

1. Tooling reuse: те же validator'ы (knowledge nuance #44 — YAML colon quoting; KOS artifact template validator — H2 headers).
2. Reader continuity: главная сессия видит отчёт в той же ментальной модели, что и артефакты.
3. Без JSON-schema versioning: markdown frontmatter менее строгий, эволюционирует мягче.

Структура отчёта:

```
---
status: returned_normally|do_not_use|error
summary: "<one-line>"
session_type: discussion|execution
---

## Result

<плотный пересказ того, что произведено>

## Tool usage

<если применимо: список вызванных tool'ов в порядке использования>

## Open follow-ups

<если применимо: то, что нужно сделать orchestrator'у на основании этого отчёта>
```

`status` в frontmatter — параллельный сигнал к `final_state` для удобства human review.

### 4.4 Anti-patterns

Контракт ЗАПРЕЩАЕТ subagent'у:

- запрашивать у пользователя что-либо через runtime-specific интерактивные tool'ы (см. §5);
- мутировать KOS task state выше уровня artifact write (то есть не делать `transition_task_workflow`);
- читать/писать секреты или environment-variables, не указанные в `context_pack.allow_list`;
- спавнить вложенные subagent'ы (одноуровневая иерархия).

## 5. owl step report CLI

**Implementation anchors.** CLI command implementation: `lib/owl/cli/internal/commands/step_report.rb` (write/read/validate flow + `--schema` and `--template` discovery flags). Storage write via `Owl::Storage::Api.write`. Dispatch entry: `lib/owl/cli/api.rb:87` (help text references this RFC §5). Public schema source: `schemas/step_report.json` (loaded by `lib/owl/subagents/internal/output_spec.rb` as `OutputSpec::SCHEMA`). Bundle injection: `lib/owl/steps/internal/bundle_builder.rb` populates `step_report_schema` for execution-typed steps so subagents see the contract without a separate round-trip.

CLI-команда `owl step report` — стандартизованный mechanism для записи и чтения отчёта subagent'а независимо от runtime.

Контракт CLI:

```
owl step report --task-id ID --step-id ID --body -|PATH
    [--format markdown]
    [--validate]

owl step report --task-id ID --step-id ID --read [--format markdown]

owl step report --schema      # dump public JSON Schema (RFC #1 §4.3) for subagent discovery
owl step report --template    # dump minimal markdown-with-frontmatter skeleton
```

Поведение:

- **Write mode (subagent → file)**: subagent в собственной сессии пишет `report_body` (см. §4.3) либо в stdin (`-`), либо в файл по PATH. CLI валидирует frontmatter и required-секции по `output_spec`. Точка сохранения — в локальной `.owl/`-структуре проекта (точный путь — TD-141).
- **Read mode (main session → report)**: orchestrator читает сохранённый отчёт; CLI вернёт markdown в stdout.

Связь с §4.3: формат `--body` входа = markdown-with-frontmatter, тот же что в §4.3. CLI — env-agnostic интерфейс над тем же форматом.

Зачем CLI вообще нужен (а не in-memory передача): runtime может не позволять прямой return из subagent в main session (см. §6 — Claude Code AskUserQuestion). CLI делает отчёт **observable артефактом**, который orchestrator может прочесть независимо от того, как именно завершилась suba-сессия.

Статус CLI: **proposed**, реализация в TD-141 (или эквиваленте). RFC закрепляет синтаксис, чтобы скиллы могли уже на этой стадии описывать flow.

## 6. Эксперимент: AskUserQuestion из subagent

Цель: проверить, доходит ли AskUserQuestion-prompt, инициированный изнутри subagent, до реального пользователя, и возвращается ли ответ обратно в subagent.

### 6.1 Setup

- Runtime: Claude Code (default Anthropic CLI).
- Subagent type: `general-purpose` (catch-all с full toolset).
- Main session: текущий /kos-orchestrator-флоу TD-140 implementing stage.
- Задание subagent: ровно один вызов AskUserQuestion с тривиальным вопросом «какой emoji выбрать для секции «Эксперимент» в RFC?», три опции (🦉 / 🔬 / 🧪).
- Constraints subagent: запрещены любые file-read/file-write и Bash-вызовы; ровно один AskUserQuestion; финальный ответ в строго заданном `EXPERIMENT_RESULT`-формате.

### 6.2 Observed output

```
EXPERIMENT_RESULT
- ask_user_question_called: false
- user_answer_received: false
- user_answer_label: null
- final_state: error
- notes: "AskUserQuestion недоступен в этом subagent — ToolSearch не нашёл такой deferred-tool."
```

Subagent в Claude Code (`general-purpose`) **не имеет в реестре tool'ов** AskUserQuestion — ни как прямой инструмент, ни как deferred-tool (отыскиваемый через ToolSearch). Соответственно, фактический вызов AskUserQuestion из subagent невозможен; subagent корректно завершился ошибкой и вернул это наблюдение.

### 6.3 Verdict

**`do-not-use`** AskUserQuestion-from-subagent как механизм коммуникации с человеком.

- В Claude Code subagent физически не имеет доступа к этому tool. Это runtime-specific факт.
- Даже если в будущем runtime разрешит — это всё равно нарушение §4.4 (subagent не должен задавать вопросы пользователю), потому что:
  - human-interaction рассинхронизирует discussion и execution session_type;
  - сделает subagent поведение runtime-specific (Codex/OpenCode не имеют эквивалента);
  - нарушает «изолированный context» свойство execution-сессии (см. §2).

### 6.4 Альтернатива

Когда subagent обнаруживает, что требуется human input, корректный flow:

1. Subagent завершается с `final_state=returned_normally` (если можно вернуть без ответа человека) или `final_state=interrupted` (если без ответа продолжить нельзя).
2. В `report_body` (§4.3) — секция `## Open follow-ups` с явным вопросом для человека.
3. Orchestrator (main session) читает отчёт через `owl step report --read` (§5), сам обращается к человеку (через runtime-specific interactive tool main-сессии — в Claude Code это AskUserQuestion).
4. Orchestrator передаёт ответ человека следующему subagent через `context_pack.intent`.

## 7. Backward compatibility

**Implementation anchors.** The breaking-switch policy is enforced by the meta-spec `spec/owl/constitution/no_legacy_mode_spec.rb:3,17` which greps `lib/owl/`, `skills/`, and `workflows/` for any reintroduction of `--legacy` flag, `OWL_LEGACY` env-var, `legacy_mode` symbol, or the removed step-level `interactive:` schema field.

RFC заявляет: переход на session-typed orchestration — **breaking switch без opt-in flag**.

Обоснование:
- Owl — personal-tool в активной разработке (Constitution §1: «Owl v1 — персональный инструмент»). Maintainer и единственный consumer — один человек, один dev environment.
- Поддерживать оба mode'а (старый монолитный + новый session-typed) удвоит сложность реализации и тестирования.
- Существующие проекты на старой архитектуре (snake/tetris) — небольшие, локальные, не in-flight. Миграция планируется отдельной задачей после approval RFC.

Конкретные шаги миграции snake/tetris **вне scope** этого RFC. Будут запланированы отдельной child-задачей; RFC лишь декларирует, что миграция — обязательная и она следует, а не предшествует, реализации новой архитектуры.

## 8. Follow-ups

После approval RFC требуются дочерние задачи в проекте Owl:

- **F-1.** Прототип реализации session_type + spawn_subagent contract в Owl-коде (TD-141 или эквивалент). Включает: декларация tier_map env-конфига, реализация `owl step report` CLI, изменения `feature` workflow YAML.
- **F-2.** Codex и OpenCode overlay'и поверх env-agnostic ядра — отдельные задачи после F-1.
- **F-3.** Обновление article 25 («Owl architecture: ARCHITECTURE.md»). После approval RFC article 25 становится частично устаревшим. Sync проводится отдельной задачей; в article 25 добавляется header «См. RFC <link-на-эту-статью>, разделы §§1–7».
- **F-4.** Миграция snake/tetris (см. §7). После приземления F-1.
- **F-5.** Опциональный prototype эксперимент для проверки §4 контракта end-to-end на реальном dummy-проекте, перед F-1.

## 9. Альтернативы (рассмотрены и отклонены)

Из analysis_report TD-140:

- **Option B (split RFC across multiple knowledge articles).** Отклонён: нарушает clarification_log Decision 1 («один deliverable»), усложняет cross-link maintenance.
- **Option C (single article + companion experiment article).** Отклонён: clarification_log Decision 3 явно запрещает внешние файлы под transcript.

Дополнительно рассмотрены и отклонены в самом RFC:

- **Three model tiers** (`fast`/`standard`/`advanced`). Отклонён: усложняет default-rules без явного use case. RFC может быть расширен ровно тем же путём, что extend session_type — добавлением одного значения, без break BC.
- **JSON-schema output contract** (вместо markdown-with-frontmatter). Отклонён: KOS уже использует md+frontmatter (artifact_requirements); reuse > novelty.
- **Per-skill tier override.** Отклонён: ведёт к рассинхронизации; tier остаётся orchestrator-level decision.

## 10. Статус RFC

- Статус: **approved** (для текущей итерации Owl v1).
- Stage в KOS workflow: TD-140 (Feature), implementing.
- Origin: parent TD-139 «Owl improvements from tetris/snake retrospective», Block A.
- Cross-link: Owl Project Constitution (article 23) §§2–4.
- Не противоречит Q1–Q15 retrospective: per-phase granularity (Q1–Q3), config_key_missing → null (Q4), 2 model tier (Q5), subagent contract без user prompts (Q6) — каждое явно повторено в §§2–6.

Следующая реальная задача после approval — TD-141 prototype (см. §8 F-1).


## 11. References

- This article: knowledge entry **id=46** in project Owl (slug `architecture_sessions_rfc`).
- Source task: **TD-140** (`RFC: architecture (sessions + tiers + env-contract)`, Feature workflow), parent **TD-139** Container retrospective.
- Stage artifacts captured during authoring: `specification`, `clarification_log`, `acceptance_criteria`, `analysis_report`, `development_plan` of TD-140.
- Constitution: knowledge article id 23 (`Owl Project Constitution`), `load_policy: required`.
- Architecture mirror: knowledge article id 25 (`Owl architecture: ARCHITECTURE.md`) — будет обновлён отдельной задачей (§8 F-3).
