---
status: approved
summary: >-
  Точечные правки 4 противоречий в source skills/commands (owl-orchestrator,
  owl-task-next, owl-step-discussion, owl-step-execution), затем bin/owl upgrade
  для рефреша .claude/, patch bump + changelog. Только доки, код не трогаем.
---

# Goal

Хирургически устранить 4 противоречия в `owl-*` скиллах/командах (выбор шага
через `owl next`; минимальный loop; дизамбигуация `done`; `review_code` reset
в step-execution), рефрешнуть materialized `.claude/`, patch-bump.

# Checklist

1. **`skills/owl-orchestrator/SKILL.md:26` (Inputs «Optional STEP-ID»).**
   Заменить «otherwise pick the first entry from `owl task ready-steps`» на
   формулировку через `owl next` (выбор шага = `dispatch_step.step_id` из
   `owl next`; явный `STEP-ID` только когда человек назвал его).
2. **`commands/owl-task-next.md:7`.** Заменить «take the first ready step»
   на «`owl next [TASK-ID] --json` — canonical next-action advisor (выдаёт
   `dispatch_step.step_id`)»; шаг 3 оставить (делегирование оркестратору).
3. **`skills/owl-step-discussion/SKILL.md:70`.** Убрать «or first ready
   entry» как механизм выбора — оставить «take the **requested** step»
   (его выбрал оркестратор через `owl next`); сохранить проверку
   `session_type: discussion`. Проверить симметрично
   `skills/owl-step-execution/SKILL.md` на аналогичную формулировку.
4. **Минимальный loop — `owl-orchestrator/SKILL.md` Workflow.** Уточнить,
   что петля ре-резолвит через `owl next` (шаг 1) каждой итерации; шаги
   2-5 (status / instructions / step show) явно помечены **опциональной
   ре-инспекцией** (часть уже сказано «optional» — довести до однозначности);
   «Loop from step 2» (стр. 60) → «Loop by re-resolving via `owl next`
   (step 1)». Без переписывания секций целиком.
5. **Дизамбигуация `done` — `owl-orchestrator/SKILL.md`.** Пройти места
   употребления `done` и уточнить смысл там, где он сливается:
   - `action.kind: done` (стр. 44) — «`owl next` action.kind `done`
     (terminal step complete)» (уже неплохо — закрепить термин);
   - «terminal step is done» (стр. 32, 60, 63, 82) → «terminal step
     **complete**» или «(step status `done`)» по контексту;
   - где речь о статусе шага (стр. 57) — «step status `done`».
   Цель: каждое употребление однозначно по одному из 4 смыслов.
6. **`review_code` reset в `skills/owl-step-execution/SKILL.md`.** Добавить
   явный абзац: при вердикте `changes_required` шаг `review_code` остаётся
   `running` (исполнитель НЕ вызывает `step complete`); повторный прогон
   требует `owl step reset TASK-ID review_code` (оператор/оркестратор),
   иначе следующий dispatch упрётся в `active_step_locked`. Зеркало
   `owl-orchestrator/SKILL.md:59`, в точке исполнения.
7. **Рефреш materialized.** Выполнить `bin/owl upgrade` — синхронизировать
   `.claude/skills/owl-*` и `.claude/commands/owl-*` (и `.opencode/` при
   наличии) с источником. Убедиться, что diff `.claude/` соответствует
   source-правкам.
8. **`lib/owl/version.rb` — patch bump**; запись в `CHANGELOG.md`
   (doc-fix: устранены противоречия owl-* скиллов). Один коммит.

# Smoke test

```
# нет stale-механизма выбора на уровне оркестратора:
grep -rn "first ready\|first entry\|pick.*first ready" skills/owl-orchestrator commands/owl-task-next.md
# review_code reset поднят в исполнителе:
grep -n "step reset\|changes_required" skills/owl-step-execution/SKILL.md
# materialized совпадает с источником после upgrade:
diff -q skills/owl-orchestrator/SKILL.md .claude/skills/owl-orchestrator/SKILL.md || echo "ОТЛИЧАЕТСЯ — проверить"
bundle exec rspec spec/owl/skills 2>&1 | tail -5
```

# Scope

- `skills/owl-orchestrator/SKILL.md`, `commands/owl-task-next.md`,
  `skills/owl-step-discussion/SKILL.md`, `skills/owl-step-execution/SKILL.md`.
- Materialized: `.claude/skills/owl-*`, `.claude/commands/owl-*` (через
  `bin/owl upgrade`, не ручной правкой).
- `lib/owl/version.rb`, `CHANGELOG.md`.
- Specs `spec/owl/skills` — прогнать, обновить только если ассертят
  изменённый текст.

# Constraints

- **Только документация.** Код `lib/owl/**` и поведение CLI не трогаем.
- Хирургические правки — не переписывать `owl-orchestrator/SKILL.md`
  целиком; корректные секции сохранить дословно.
- Materialized `.claude/` обновлять ТОЛЬКО через `bin/owl upgrade`
  (не ручной правкой) — иначе рассинхрон источник↔копия.
- Исполнители сохраняют приём явного `STEP-ID` (его выбрал оркестратор);
  убираем только «first ready entry» как самостоятельный выбор.
- patch bump (doc-fix без изменения поведения).

# Files to inspect

- `skills/owl-orchestrator/SKILL.md` (Inputs стр. 26; Workflow шаги 1-9,
  особ. стр. 44/57/60/63/82; Notes стр. 96).
- `commands/owl-task-next.md` (стр. 7).
- `skills/owl-step-discussion/SKILL.md` (стр. 70).
- `skills/owl-step-execution/SKILL.md` (review/`changes_required` точка;
  стр. ~84/130 для контекста).
- `skills/owl-cli/SKILL.md:81` (reference `owl step reset` — НЕ менять,
  свериться на согласованность).
- `lib/owl/version.rb`, `CHANGELOG.md`.

# Tests and verification

- `bundle exec rspec spec/owl/skills` (seeded_sources / api) зелёный;
  при необходимости обновить ассерты под новый текст.
- Grep-инварианты из Smoke test проходят.
- `diff` источник↔`.claude/` после `bin/owl upgrade` пуст.
- Полный `bundle exec rspec` зелёный (документация не должна ничего ломать).
- Проверить вручную: смысл каждого `done` в orchestrator однозначен;
  loop читается как ре-резолв через `owl next`.

# Out of scope

- Любые изменения кода `lib/owl/**` / поведения CLI.
- Переписывание скиллов сверх 4 названных пунктов.
- Прочие health-review задачи (0041/0048/0049).
- Ручная правка `.claude/` мимо `bin/owl upgrade`.
