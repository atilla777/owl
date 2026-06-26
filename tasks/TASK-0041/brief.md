---
status: approved
summary: Устранить пересечение команд task ready/available, синхронизировать дрейф owl.version в config.yaml и очищать current-указатель при удалении текущей задачи.
---

# Brief

## Problem

Три мелкие болячки консистентности/UX, выявленные при health-review 2026-06-26:

1. **ready/available пересекаются.** `owl task available` и `owl task ready`
   почти дублируют друг друга (обе возвращают runnable-задачу, лишь с разной
   схемой ответа). `owl task ready` был добавлен в TASK-0026 (межзадачные
   зависимости / blocks-blocked-by DAG), но на него не ссылается ни один скилл —
   команда читается как «сирота», и у агента нет указания, когда какую брать.
2. **Дрейф версии в конфиге.** `.owl/config.yaml` хранит `owl.version: 0.15.1`,
   тогда как гем уже `0.20.0` — устаревший показатель версии.
3. **delete оставляет висячий current-указатель.** `owl task delete` не чистит
   `.owl/local/current.yaml`: после удаления текущей задачи `owl task current`
   начинает возвращать `task_not_found` вместо «нет текущей задачи».

## Goal

- У двух «ready/available» команд есть задокументированное, непересекающееся
   назначение (документируем, не удаляем — см. Edge cases).
- Версия в `.owl/config.yaml` отслеживает версию гема (синхронизируется на
   `owl upgrade`).
- Удаление текущей задачи не оставляет висячего current-указателя.

Решаемые проблемы малы и хорошо понятны — workflow `quick` подходит; `feature`
с дизайном/планом не нужен.

## Scenarios

### Requirement: Delete clears current pointer

`owl task delete` SHALL очищать current-указатель, когда удаляемая задача
является текущей.

#### Scenario: Удаление текущей задачи
- WHEN current-указатель равен TASK-X и выполняется `owl task delete TASK-X --force`
- THEN `owl task current` сообщает об отсутствии текущей задачи, а не `task_not_found`
- AND `.owl/local/current.yaml` не содержит ссылки на удалённый TASK-X

#### Scenario: Удаление не-текущей задачи
- WHEN current-указатель равен TASK-A и выполняется `owl task delete TASK-B --force`
- THEN current-указатель остаётся равным TASK-A (нетронут)

### Requirement: ready/available disambiguated

owl-cli skill SHALL явно указывать, когда использовать `owl task available`,
а когда `owl task ready`, чтобы ни одна из команд не читалась как неоднозначный
дубликат.

#### Scenario: Агенту нужна runnable-задача
- WHEN агент спрашивает «что я могу взять в работу?»
- THEN ровно одна задокументированная команда (`owl task available`) отвечает на
  выбор работы, а назначение `owl task ready` (dependency-ready по DAG) описано
  отдельно, без неоднозначного дубля

### Requirement: Config version tracks the gem

`owl upgrade` SHALL приводить `owl.version` в `.owl/config.yaml` в соответствие
с `Owl::VERSION`.

#### Scenario: upgrade синхронизирует версию
- WHEN `.owl/config.yaml` хранит устаревший `owl.version` и выполняется `owl upgrade`
- THEN после команды `owl.version` равен `Owl::VERSION`

#### Scenario: обычные команды версию не трогают
- WHEN выполняется любая не-`upgrade` команда (например `owl status`)
- THEN `owl.version` в конфиге не переписывается этой командой

## Edge cases

- **Удаление `task ready` отвергнуто.** Это изменение CLI-поверхности (публичный
  контракт команды), потенциально ломающее для любого внешнего потребителя.
  Выбран путь документирования разницы, а не удаления.
- **Синхронизация версии только на `owl upgrade`**, а не молча на каждой команде —
  иначе любая read-команда стала бы мутирующей записью в конфиг (нарушение
  ожиданий идемпотентности и source-of-truth).
- **Удаление не-текущей задачи** не должно затрагивать current-указатель.
- **Идемпотентность:** повторный `owl task current` после удаления текущей —
  чистый «нет текущей задачи», без ошибок.

## Acceptance criteria

- `owl task delete <current> --force` оставляет `owl task current` чистым (нет
  `task_not_found`); покрыто спецификацией.
- Удаление не-текущей задачи не меняет current-указатель; покрыто спецификацией.
- После `owl upgrade` `.owl/config.yaml owl.version` совпадает с `Owl::VERSION`;
  покрыто спецификацией.
- Разграничение `owl task available` vs `owl task ready` зафиксировано в
  owl-cli skill (`skills/owl-cli/SKILL.md`); ни одна команда не удалена.
- Соблюдены правила слоёв (`docs/agents/27`): доступ к `.owl/`/`tasks/` идёт
  через внутренние сервисы, не сырыми FS-вызовами; если затрагивается
  `lib/owl/**/api.rb` — добавить покрытие до 100% строк (`docs/agents/30`).
- Bump `Owl::VERSION` + запись в `CHANGELOG.md` в том же коммите (изменения в
  `lib/**` и `skills/**` — patch-уровень SemVer: фиксы + обратносовместимое
  уточнение документации).
