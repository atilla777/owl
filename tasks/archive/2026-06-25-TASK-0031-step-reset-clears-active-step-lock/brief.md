---
status: approved
summary: "owl step reset должен чистить active-step-lock (как делает step complete). Сейчас reset меняет статус running→pending, но lock-файл .owl/local/active_steps/<TASK>.yaml остаётся указывать на сброшенный шаг, вклинивая задачу: нельзя start/complete другой шаг."
---

# Problem

`owl step reset <TASK> <STEP>` переводит running-шаг обратно в `pending`
(`Steps::Api.reset` → `StatusWriter`), но **не чистит** active-step-lock
(`.owl/local/active_steps/<TASK-ID>.yaml`). Этот per-task lock пишется на
`step start` и снимается только в CLI-команде `step_complete.rb`
(`ActiveStepLock.clear` после успешного `Api.complete`). Команда `step_reset.rb`
аналогичного `clear` не делает.

Последствие (воспроизведено в этой сессии при работе над TASK-0030): после
`step reset` lock продолжает указывать на сброшенный шаг, и **любой** последующий
`step start`/`step complete` другого шага той же задачи отвергается с
`active-step lock relates to a different step` — задача вклинивается, пока вручную
не удалить lock-файл (то же, что внутри делает `step complete`).

# Goal

Сделать так, чтобы `owl step reset` снимал active-step-lock для сброшенного шага
(идемпотентно, безопасно), тем же приёмом, что и `step complete`. После reset
задача снова свободна для `step start`/`step complete` любого ready-шага.

# Scenarios

### Requirement: reset снимает active-step-lock

The system SHALL clear the active-step lock for a step when that step is reset.

#### Scenario: reset освобождает задачу
- WHEN шаг `S` находится в `running` (есть lock `.owl/local/active_steps/<T>.yaml`
  с `step_id: S`), и выполняется `owl step reset <T> S`
- THEN статус `S` становится `pending`
- AND active-step-lock для `<T>` снят (файл отсутствует)
- AND последующий `owl step start <T> S` (или другого ready-шага) проходит без
  ошибки `different step`

### Requirement: clear не трогает чужой lock и идемпотентен

The system SHALL only clear the lock when it refers to the reset step, and SHALL
be a no-op when no lock is present.

#### Scenario: нет лока — reset не падает
- WHEN lock-файла для задачи нет, а шаг почему-то в `running`
- THEN `owl step reset` завершается успешно (clear — no-op, `:absent`)

#### Scenario: lock про другой шаг — не снимаем
- WHEN lock задачи указывает на шаг `X`, а запрошен `reset` шага `Y`
- THEN lock шага `X` НЕ снимается (clear только при совпадении task_id+step_id)

# Edge cases

- **Совпадение шага.** Снимать lock только если `ActiveStepLock.matches?(payload,
  task_id, step_id)` — не сносить lock другого активного шага задачи (per-task lock
  один, но защищаемся явно).
- **Идемпотентность.** `ActiveStepLock.clear` уже возвращает `:absent`, если файла
  нет — повторный reset/отсутствие лока безопасны.
- **Где чистить.** По аналогии со `step_complete.rb` — на уровне CLI-команды
  `step_reset.rb` после успешного `Api.reset` (а не в `Api.reset`, чтобы не менять
  контракт чистого Api-слоя и совпасть с существующим паттерном).
- **reset только running.** `Api.reset` и так отвергает не-running шаг
  (`step_not_running`) — clear вызывается лишь на успешном пути.
- **Версионирование.** Багфикс, back-compat → patch bump VERSION + CHANGELOG.

# Acceptance criteria

- [ ] `owl step reset` снимает active-step-lock сброшенного шага (по аналогии с
  `step complete`), только при совпадении task_id+step_id; no-op при отсутствии лока.
- [ ] После `reset` задача свободна: `step start`/`step complete` другого ready-шага
  не падают с `different step`.
- [ ] Регрессионный тест: reset running-шага → lock снят; reset без лока → успех;
  lock другого шага не затронут.
- [ ] patch bump `Owl::VERSION` + CHANGELOG; RuboCop net-zero; rspec зелёный;
  100% покрытие тронутых `**/api.rb` (если затронут Api).
