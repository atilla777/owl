---
status: approved
summary: "Три CLI-UX фикса из полевого отчёта re: subcommand-help для групп команд, hint на takeover running-шага, и re-read состояния в выводе child create --brief."
---

# Problem

Полевая работа с Owl в consumer-проекте (`re`) выявила три CLI-шероховатости, которые
сбивали агента:

1. **Нет subcommand-help.** `owl step` и `owl step --help` падают с
   `unknown_command` вместо списка подкоманд (`start|complete|reopen|skip|reset|show|
   report`). Агент не может узнать доступные подкоманды группы, не читая `owl --help`
   или код. То же для других групп (`task`, `workflow`, `artifact`).
2. **Takeover running-шага неочевиден.** После `owl task claim --steal` на задаче с
   шагом в статусе `running` шаг остаётся `running`; `owl step reopen` не помогает (он
   только для `done`); рабочая команда — `owl task adopt`. Но ничто на это не указывает,
   агент тратит попытки.
3. **`owl task child create --brief` печатает stale payload.** Сразу после prefill
   brief вывод показывает `brief: pending`, хотя фактически `brief: done` (видно в
   `owl status`). Вывод не перечитывает состояние задачи после prefill — это
   дезинформирует агента и провоцирует лишние действия.

# Goal

Убрать эти три источника трения: дать информативный subcommand-help, явный путь
takeover для running-шага, и корректный (актуальный) JSON-вывод `child create --brief`.

# Scenarios

### Requirement: Группы команд показывают свои подкоманды

#### Scenario: owl step без подкоманды печатает список подкоманд
- WHEN пользователь выполняет `owl step` или `owl step --help`
- THEN вывод перечисляет доступные подкоманды группы (start, complete, reopen, skip,
  reset, show, report, ...) и завершается успехом (exit 0), а не `unknown_command`

#### Scenario: то же для прочих групп
- WHEN пользователь выполняет `owl task --help` / `owl workflow --help` /
  `owl artifact --help`
- THEN каждая печатает свои подкоманды

### Requirement: Takeover running-шага подсказан явно

#### Scenario: claim --steal на running-шаге подсказывает adopt
- WHEN пользователь выполняет `owl task claim TASK-ID --steal` на задаче, чей шаг в
  статусе `running`
- THEN ответ содержит явный hint, что для перехвата running-шага нужен
  `owl task adopt TASK-ID` (который переклеймит lease и сбросит залипший шаг)

#### Scenario: owl next сигналит needs_adopt
- WHEN running-шаг с истёкшим lease выбран для takeover
- THEN `owl next` уже возвращает `needs_adopt: true` (существующее поведение) — этот
  путь согласован с hint из claim --steal

### Requirement: child create --brief печатает актуальное состояние

#### Scenario: prefilled brief показан как done
- WHEN пользователь выполняет `owl task child create … --brief …` (с prefill brief)
- THEN JSON-вывод отражает фактический пост-prefill статус шага (`brief: done`), а не
  устаревший `brief: pending`

# Edge cases

- **Формат help.** Subcommand-help в JSON-режиме (`--json`) должен оставаться
  машиночитаемым (структурированный список), а в обычном — человекочитаемым. Не ломать
  существующий `owl --help`.
- **Exit codes.** `owl step --help` → exit 0 (это help, не ошибка). Сохранить
  exit-семантику ошибок для реально неизвестных подкоманд (`owl step bogus` →
  `unknown_command`, exit как сейчас).
- **Hint неблокирующий.** Hint в `claim --steal` — дополнительное поле, не меняет
  успех/код операции; существующие потребители ответа не ломаются.
- **child create без --brief.** Поведение без `--brief` не меняется.
- **Версионирование.** Изменения `lib/**`/CLI — bump `Owl::VERSION` (minor — новые
  affordances) + `CHANGELOG.md`.

# Acceptance criteria

- [ ] `owl <group>` и `owl <group> --help` для `step`/`task`/`workflow`/`artifact`
  печатают список подкоманд, exit 0; неизвестная подкоманда по-прежнему
  `unknown_command`.
- [ ] `owl task claim --steal` на задаче с running-шагом возвращает hint про
  `owl task adopt` (поле в JSON + строка в человекочитаемом выводе).
- [ ] `owl task child create … --brief …` возвращает актуальный статус шага
  (`brief: done`) — вывод перечитывает состояние после prefill.
- [ ] Тесты на каждый из трёх сценариев.
- [ ] `bundle exec rspec` зелёный; 100% покрытие затронутых `lib/owl/**/api.rb`;
  RuboCop net-zero на трогаемых файлах.
- [ ] `Owl::VERSION` поднят + запись в `CHANGELOG.md`.

# Out of scope

- `--brief-body -` для child (ввод тела brief через stdin) и overlay-доки — TASK-0024.
- Изменение самого механизма takeover/adopt (только hint, не новая логика).
