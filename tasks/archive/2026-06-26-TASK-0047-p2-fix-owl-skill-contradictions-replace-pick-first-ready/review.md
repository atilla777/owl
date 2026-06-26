---
status: resolved
summary: >-
  Все 4 противоречия owl-* скиллов устранены хирургически; materialized .claude/
  идентичны источнику; done дизамбигуирован; review_code reset поднят в
  step-execution; только доки, код/CLI не тронуты; specs зелёные. Verdict: accepted.
verdict: accepted
ready: true
---

# Summary

Self-review правок TASK-0047 — устранение 4 противоречий в orchestration-скиллах
и командах (`skills/owl-*`, `commands/owl-*`). Проверены: корректность доки-фиксов,
хирургичность (нет переписывания load-bearing `owl-orchestrator/SKILL.md`,
корректные секции сохранены дословно), отсутствие изменений кода/поведения CLI,
внутренняя согласованность и синхрон materialized-копий. Все пункты brief AC и
plan выполнены. Verdict: **accepted**.

# Findings

## AC1 — единый канон выбора шага (`owl next`) — PASS

- `commands/owl-task-next.md:7`: «take the first ready step» → `owl next … →
  action.dispatch_step.step_id` с явной анти-инструкцией «do not pick the first
  ready step by hand». Корректно.
- `skills/owl-orchestrator/SKILL.md:26` (Inputs): «pick the first entry from
  `owl task ready-steps`» → «chosen for you by `owl next` … its
  `dispatch_step.step_id` … Do not pick the step yourself». Корректно.
- `skills/owl-step-discussion/SKILL.md:48` (Inputs) и `:70` (Workflow шаг 2):
  «STEP-ID chosen from ready-steps» / «take the requested or first ready entry»
  → берётся **requested** шаг (выбран оркестратором через `owl next`); приём
  явного `STEP-ID` и проверка `session_type: discussion` сохранены; добавлен
  cross-check против ready-steps «if unsure». Исполнитель корректно НЕ выбирает
  шаг сам.
- Grep-инвариант: единственные оставшиеся вхождения «first ready / first entry» —
  `owl-task-next.md:7` и `owl-orchestrator/SKILL.md:96` — обе **анти-инструкции**
  («do not pick…», «never pick the first entry of `owl task list`»), закрепляющие
  канон, а не механизм выбора. Это ожидаемо и должно остаться.

## AC2 — минимальный loop оркестратора — PASS

- `owl-orchestrator/SKILL.md:48`: шаг 2 помечен «**Optional re-inspection** (steps
  2–4 are optional; `owl next` в step 1 уже возвращает всё нужное)».
- `:60` (шаг 7): «Loop from step 2» → «**Loop by re-resolving via `owl next`
  (step 1)** each iteration». Петля теперь явно ре-резолвит через `owl next`,
  а не ре-деривит ладдер. Корректно.

## AC3 — дизамбигуация `done` — PASS

Просмотрены все вхождения `done` в `owl-orchestrator/SKILL.md`:
- `:32`, `:57`, `:63`, `:82` — «complete (step status `done`)» / «is not complete
  (its step status is not yet `done`)» — терминальный шаг однозначно по статусу.
- `:44` — «`owl next`'s `action.kind: done`: … complete (step status `done`)» —
  чётко развести action-kind vs step-status.
- `:48` — `progress {done, total, pct}` — имя поля в payload, иной смысл,
  не путается, корректно оставлено.
Каждое употребление однозначно соотносится с одним из смыслов.

## AC4 — `review_code` reset поднят в `owl-step-execution` — PASS

- `skills/owl-step-execution/SKILL.md:89`: добавлена секция «Review steps
  (`review_code` and `changes_required`)»: `changes_required` оставляет шаг
  `running` (исполнитель НЕ вызывает `step complete`); повторный прогон требует
  `owl step reset TASK-ID review_code`, иначе следующий dispatch упрётся в
  `active_step_locked`; явная отсылка «mirrors `owl-orchestrator/SKILL.md`'s
  post-delegation rule».
- Согласованность подтверждена: `owl-orchestrator/SKILL.md:59` описывает то же
  правило для оркестратора; `owl-cli/SKILL.md:81` (`owl step reset … —
  `changes_required` re-run`) — reference-команда. Три точки согласованы, дублей-
  противоречий нет.

## AC5 — рефреш materialized `.claude/` — PASS

`diff -q` источник↔`.claude/` для всех 4 файлов
(`owl-orchestrator`, `owl-task-next`, `owl-step-discussion`, `owl-step-execution`)
→ идентичны. `.opencode/` в репо отсутствует. Рефреш через `bin/owl upgrade`.

## AC6 — версия / CHANGELOG — PASS

`Owl::VERSION` 1.1.0 → 1.1.1 (patch — корректно для doc-only без изменения
поведения, по Конституции §7.1). `CHANGELOG.md` запись под `### Fixed` с точным,
полным описанием всех 5 правок + рефреша. `Gemfile.lock` (1.1.1) и
`.owl/config.yaml` (owl.version 1.1.1) — ожидаемые side-effects bump'а + upgrade,
не дефекты.

## AC7 — только доки, без изменений кода/CLI — PASS

В диффе нет `lib/owl/**` и `bin/owl`. Изменены только `.md` скиллы/команды,
`version.rb`, `CHANGELOG.md` + сгенерированные `Gemfile.lock`/`.owl/config.yaml`.
Поведение CLI не тронуто.

## Хирургичность — PASS

`owl-orchestrator/SKILL.md` не переписан целиком: 16 строк изменено (8 hunk'ов),
все точечные; корректные секции (Plan-approval gate, composite-handoff, stop
conditions) сохранены дословно. Семантического дрейфа в load-bearing скилле нет.

## Тесты — PASS

- `bundle exec rspec spec/owl/skills`: 60 examples, 0 failures.
- Полный `bundle exec rspec`: 2063 examples, 0 failures, 1 pending.
- SimpleCov показывает per-file 0.0% при частичном прогоне (`spec/owl/skills`) —
  известный wart partial-run покрытия, судим по числу failures (0), не по
  coverage-хвосту. Полный прогон зелёный.

# Resolution

Все 7 acceptance criteria выполнены, дефектов не найдено. Шаг завершается
нормально (`owl step complete`).

# Remediation

Не требуется — `changes_required`-findings отсутствуют.

# Residual risks

- Низкий. Правки доки-точечные; specs не ассертят изменённый прозаический текст
  (60/60 зелёные без правки ассертов) → текстовых регрессий нет.
- Минорное наблюдение (не дефект, не блокер): `owl-orchestrator/SKILL.md:45`
  («the terminal step is not done») сохраняет разговорную форму «done» вместо
  «complete / step status `done`», но контекст (`stop_blocked`, терминальный шаг)
  делает смысл однозначным; brief не относил эту строку к hot-spots. Правки не
  требует.
- Распространение на consumer-проекты (re/Rrrog, tetris) — обычным путём:
  push → `owl self-update` → `owl upgrade` в каждом проекте.
