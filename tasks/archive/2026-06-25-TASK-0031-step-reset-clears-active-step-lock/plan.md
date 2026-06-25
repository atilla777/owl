---
status: approved
summary: "В step_reset.rb после успешного Api.reset условно снять active-step-lock (matches → clear). Регрессионный тест на CLI-уровне. patch bump + CHANGELOG."
---

# Goal

`owl step reset` снимает active-step-lock сброшенного шага (зеркало
`step_complete.rb`), только при совпадении task_id+step_id; задача после reset
свободна для start/complete другого ready-шага.

# Scope

- `lib/owl/cli/internal/commands/step_reset.rb` — после успешного `Api.reset`
  добавить условный `ActiveStepLock.clear`.
- `lib/owl/version.rb` + `CHANGELOG.md` — patch bump (0.16.0 → 0.16.1).

# Constraints

- НЕ менять `Owl::Steps::Api.reset` и `step_complete.rb`.
- clear только при `ActiveStepLock.matches?(payload, task_id:, step_id:)`; no-op без лока.
- RuboCop net-zero; rspec зелёный; покрытие `**/api.rb` не страдает (Api не меняется).
- Constitution §7.1: patch bump VERSION + CHANGELOG в том же коммите.

# Files to inspect

- `lib/owl/cli/internal/commands/step_reset.rb` (run — куда вставить).
- `lib/owl/cli/internal/commands/step_complete.rb` (паттерн clear на стр.42, load/matches на 86-88).
- `lib/owl/steps/internal/active_step_lock.rb` (load/clear/matches? API).
- `spec/owl/cli/**/step_reset*` или соответствующий CLI/integration спек — куда добавить регрессию.

# Checklist

- [ ] В `StepReset.run`, после `return ... if result.err?` (успешный reset),
      загрузить lock (`ActiveStepLock.load(root:, task_id:)`) и, если
      `matches?(payload, task_id: options[:task_id], step_id: options[:step_id])`,
      вызвать `ActiveStepLock.clear(root:, task_id: options[:task_id])`.
- [ ] Добавить require на `active_step_lock` в step_reset.rb (как в step_complete.rb).
- [ ] `CHANGELOG.md`: запись (Fixed) — `owl step reset` теперь снимает active-step-lock,
      устраняя вклинивание задачи (нельзя было start/complete другой шаг).
- [ ] `lib/owl/version.rb`: 0.16.0 → 0.16.1.

# Tests and verification

- [ ] reset running-шага с активным lock этого шага → после reset lock-файл
      отсутствует; `step start` другого ready-шага успешен.
- [ ] reset без lock-файла → reset успешен (no-op clear).
- [ ] lock указывает на шаг X, reset шага Y (если такое состояние достижимо в тесте)
      → lock X не снят. (Если недостижимо обычным путём — покрыть на уровне
      matches?-условия unit-стилем.)
- [ ] `bundle exec rspec` зелёный, 0 failures; покрытие `**/api.rb` без регрессий.
- [ ] `bundle exec rubocop lib/owl/cli/internal/commands/step_reset.rb` net-zero.

# Smoke test

```
# на реальной задаче (или throwaway quick):
owl step start <T> <STEP>           # lock пишется
owl step reset <T> <STEP>           # статус pending + lock снят
ls .owl/local/active_steps/<T>.yaml # отсутствует
owl step start <T> <STEP>           # проходит без 'different step'
```

# Out of scope

- Изменение семантики `Api.reset` (остаётся чистым статус-переходом).
- mismatch-реджект в reset (не требуется для багфикса).
- scoped-staging commit-push (отдельная задача, фикс #2).
