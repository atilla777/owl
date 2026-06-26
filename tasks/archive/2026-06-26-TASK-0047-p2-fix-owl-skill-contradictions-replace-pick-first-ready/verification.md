---
status: passed
summary: >-
  Устранены 4 противоречия в owl-* скиллах/командах (выбор шага через owl next;
  минимальный loop; дизамбигуация done; review_code reset в step-execution);
  .claude рефрешнут через owl upgrade; patch bump 1.1.1; все проверки зелёные.
---

# Summary

Хирургические правки только в документации orchestration-скиллов/команд
(`skills/owl-*`, `commands/owl-*`) — код `lib/owl/**` и поведение CLI не
тронуты. Реализованы все 6 пунктов плана + рефреш materialized-копий и
patch-bump:

1. **Канон выбора шага = `owl next`.** Убран stale-механизм «pick/take first
   ready step» в `owl-orchestrator/SKILL.md` Inputs (стр. 26),
   `commands/owl-task-next.md:7` (теперь `owl next … → action.dispatch_step.step_id`),
   `owl-step-discussion/SKILL.md` (Workflow стр. 70 + Inputs стр. 48: берётся
   **requested** шаг, выбранный оркестратором через `owl next`).
2. **Минимальный loop.** Workflow шаг 2 помечен «Optional re-inspection
   (steps 2–4 optional)»; «Loop from step 2» → «Loop by re-resolving via
   `owl next` (step 1)» (стр. 60).
3. **Дизамбигуация `done`.** Все горячие точки (стр. 32/44/57/60/63/82)
   уточнены до однозначных смыслов: `owl next` `action.kind: done` /
   step status `done` / terminal step complete.
4. **`review_code` reset в `owl-step-execution`.** Добавлена секция «Review
   steps (`review_code` and `changes_required`)»: вердикт `changes_required`
   оставляет шаг `running` (исполнитель НЕ вызывает `step complete`),
   повторный прогон требует `owl step reset TASK-ID review_code`, иначе
   следующий dispatch упрётся в `active_step_locked`.
5. **Рефреш materialized.** `bin/owl upgrade` синхронизировал
   `.claude/skills/owl-*` и `.claude/commands/owl-*` (`.opencode/` в репо
   отсутствует). Заменены ровно 4 отредактированных файла.
6. **Версия.** `Owl::VERSION` 1.1.0 → 1.1.1 (patch, doc-fix) + запись в
   `CHANGELOG.md`.

# Commands

```
# grep-инвариант: нет stale-механизма выбора (остались только анти-инструкции)
grep -rn "first ready|first entry|pick.*first ready|take the first" \
  skills/owl-orchestrator commands/owl-task-next.md
# → 2 совпадения, оба — отрицания канона («do not pick…», «never pick…»)

# review_code reset поднят в исполнителе
grep -n "step reset|changes_required" skills/owl-step-execution/SKILL.md
# → присутствует (секция + инструкция owl step reset)

# materialized совпадает с источником после upgrade
diff -q skills/owl-orchestrator/SKILL.md .claude/skills/owl-orchestrator/SKILL.md
diff -q commands/owl-task-next.md       .claude/commands/owl-task-next.md
diff -q skills/owl-step-discussion/SKILL.md .claude/skills/owl-step-discussion/SKILL.md
diff -q skills/owl-step-execution/SKILL.md  .claude/skills/owl-step-execution/SKILL.md
# → все идентичны

bundle exec rspec spec/owl/skills
bundle exec rspec
```

# Outcomes

- **grep-инвариант (выбор шага):** OK. Остались только две формулировки —
  `commands/owl-task-next.md:7` («do not pick the first ready step by hand»)
  и `owl-orchestrator/SKILL.md:96` («never pick the first entry of
  `owl task list`») — это анти-инструкции, закрепляющие канон `owl next`,
  а не механизм выбора. Stale-механизма «first ready entry» больше нет.
- **grep-инвариант (review_code reset):** OK — секция и `owl step reset
  TASK-ID review_code` присутствуют в `owl-step-execution/SKILL.md`.
- **diff источник↔`.claude/`:** OK — все 4 файла идентичны после
  `bin/owl upgrade` (`replaced` = ровно эти 4 файла).
- **`bundle exec rspec spec/owl/skills`:** 60 examples, 0 failures.
- **Полный `bundle exec rspec`:** 2063 examples, 0 failures, 1 pending.
- **Версия/CHANGELOG:** 1.1.1 записан, запись в `CHANGELOG.md` под `### Fixed`.

# Not run

- Ручной прогон оркестратора end-to-end не выполнялся — изменение
  документационное, поведение CLI не менялось; покрытия spec/owl/skills +
  полного rspec достаточно.

# Failures or blockers

Нет. Все проверки зелёные.

# Residual risks

- Низкий. Правки точечные, корректные секции скиллов сохранены дословно;
  load-bearing `owl-orchestrator/SKILL.md` не переписывался.
- Specs не ассертят изменённый прозаический текст (60/60 зелёные без правки
  ассертов), поэтому регрессий по тексту нет.
- Распространение на consumer-проекты (re/Rrrog, tetris) произойдёт обычным
  путём: push → `owl self-update` → `owl upgrade` в каждом проекте.
