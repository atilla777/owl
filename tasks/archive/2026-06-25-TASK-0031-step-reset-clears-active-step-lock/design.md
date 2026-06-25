---
status: shipped
summary: "Добавить ActiveStepLock.clear в CLI-команду step_reset.rb после успешного Api.reset, только при совпадении lock (task_id+step_id). Зеркалит существующий приём step_complete.rb. Api.reset не трогаем."
---

# Context

`owl step reset` (`lib/owl/cli/internal/commands/step_reset.rb`) зовёт
`Owl::Steps::Api.reset`, который переводит running-шаг в `pending`, но не снимает
per-task active-step-lock (`.owl/local/active_steps/<TASK>.yaml`). Lock пишется на
`step start` и снимается в `step_complete.rb:42`
(`ActiveStepLock.clear(root:, task_id:)` после успешного `Api.complete`).
`step_reset.rb` аналогичного вызова не делает → задача вклинивается.

# Decision

Зеркалить приём `step_complete.rb`: в `step_reset.rb`, после успешного
`Api.reset` (result.ok?), вызвать `ActiveStepLock.clear(root:, task_id:)` — но
**только если** текущий lock относится к сбрасываемому шагу
(`ActiveStepLock.load` + `matches?(payload, task_id:, step_id:)`). Это:
- освобождает задачу для последующих `step start`/`complete`;
- не сносит lock другого шага (защита, хотя per-task lock один);
- идемпотентно (нет лока → no-op).

Логику держим на CLI-уровне (как у complete), не в `Api.reset`, чтобы:
- не менять контракт чистого Api-слоя;
- совпасть с существующим паттерном (lock — это CLI/runtime-забота, Api оперирует
  статусами шагов в task.yaml).

# Alternatives

- **Чистить безусловно (как complete на стр.42).** complete ДО этого реджектит
  mismatch (`lock_mismatch_response`), поэтому там безусловный clear безопасен. У
  reset такой проверки нет; безусловный clear мог бы снести lock другого шага.
  Поэтому — clear только при `matches?`. Чище и безопаснее.
- **Вызывать clear внутри `Api.reset`.** Смешало бы runtime-lock с доменным
  Api-слоем и разошлось бы с тем, как это сделано для complete. Отклонено.
- **Добавить mismatch-реджект в reset (как в complete).** Избыточно для багфикса;
  reset по смыслу — аварийный сброс, не требует строгой mismatch-семантики. Достаточно
  условного clear.

# Risks

- **Снос чужого лока.** Исключено условием `matches?`.
- **Регрессия complete-пути.** Не трогаем `step_complete.rb`/`Api`. Низкий риск.
- **Покрытие.** Меняется CLI-команда (не `api.rb`). Если тесты идут через CLI-уровень
  — добавить кейсы туда. Покрытие `**/api.rb` не страдает (Api не меняется).

# API

- **CLI:** `owl step reset` теперь снимает active-step-lock сброшенного шага.
  Сигнатура/вывод команды не меняются (lock — побочный runtime-эффект).
- **Ruby:** правка только в `Owl::Cli::Internal::Commands::StepReset.run` —
  добавление `ActiveStepLock.load` + условный `ActiveStepLock.clear`. `Steps::Api.reset`
  без изменений.
