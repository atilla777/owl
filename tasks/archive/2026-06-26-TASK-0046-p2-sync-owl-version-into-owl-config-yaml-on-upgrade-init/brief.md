---
status: approved
summary: >-
  Экспонировать версию Owl через CLI: config get version (алиас на owl.version),
  config show (показать owl-блок с версией) и новая команда owl version (gem vs
  project-stamped, с индикацией расхождения). Синхрон на init/upgrade уже есть —
  закрепить регресс-тестом. Аддитивно → minor bump.
---

# Problem

Версия Owl, под которой материализован проект, штампуется в
`.owl/config.yaml` под ключом `owl.version`:

- `owl init` пишет `owl.version = Owl::VERSION` (`lib/owl/init/api.rb:33`);
- `owl upgrade` пере-штампует его (`refresh.rb#stamp_version`, строки
  151-157).

То есть **синхрон на init/upgrade уже работает**. Но версия фактически не
доступна пользователю стандартными путями:

1. **`owl config get version` → `null`.** Каноничный ключ — `owl.version`,
   а top-level `version` отсутствует; пользователь, естественно, пробует
   `config get version` и получает `null`.
2. **`owl config show` не показывает `owl`-блок вообще** — в выводе только
   `project` / `settings` / `storage`, штампованная версия невидима.
3. **Нет команды `owl version`.** Есть только флаг `owl --version`,
   который печатает версию *гема* (`Owl::VERSION`), а не штампованную в
   проекте `owl.version`. Их различие значимо: гем мог обновиться без
   повторного `owl upgrade` (ровно случай этого self-hosted репозитория:
   gem = 1.0.0, а `owl.version` = 0.21.0).

Health-review-находка (label `health-review-2026-06-26`). Задача — про
**экспозицию** версии, а не про сам синхрон (он есть).

# Goal

Сделать версию Owl доступной и наблюдаемой через CLI, не ломая существующий
синхрон:

- `owl config get version` возвращает штампованную версию (алиас на
  `owl.version`), а не `null`;
- `owl config show` показывает `owl`-блок (в т.ч. `version`);
- новая команда `owl version` печатает версию гема (`Owl::VERSION`) и
  штампованную в проекте (`owl.version`), явно сигналя расхождение (drift);
- синхрон `owl.version` на `init`/`upgrade` подтверждён регресс-тестом
  (защита от регрессии, не новый код).

Изменения аддитивны (новая команда, новый алиас, расширение вывода
`config show`), миграции данных нет → **minor bump** `Owl::VERSION` +
запись в `CHANGELOG.md`. Хранилищный ключ остаётся `owl.version`
(top-level `version` — только алиас на чтение).

# Scenarios

### Requirement: config get version возвращает штампованную версию

The system SHALL resolve `owl config get version` to the value of
`owl.version` from `.owl/config.yaml` instead of returning null.

#### Scenario: get version после init

- WHEN проект инициализирован (`owl init`) и пользователь выполняет
  `owl config get version --json`
- THEN ответ содержит `value` равный штампованной `owl.version`
- AND `value` не равен `null`

#### Scenario: канонический ключ продолжает работать

- WHEN пользователь выполняет `owl config get owl.version --json`
- THEN возвращается то же значение, что и для `config get version`

### Requirement: config show показывает owl-блок

The system SHALL include the `owl` block (with its `version`) in the
output of `owl config show`.

#### Scenario: show содержит версию

- WHEN пользователь выполняет `owl config show --json`
- THEN вывод содержит `owl.version` со штампованным значением

### Requirement: команда owl version

The system SHALL provide an `owl version` command that prints both the
running gem version (`Owl::VERSION`) and the project-stamped version
(`owl.version`).

#### Scenario: обе версии и индикация расхождения

- WHEN пользователь выполняет `owl version --json`
- THEN вывод содержит версию гема и штампованную версию проекта
- AND при их различии вывод явно сигналит drift (например `up_to_date:
  false` или эквивалент)

#### Scenario: версии совпадают

- WHEN gem-версия и штампованная версия равны
- THEN вывод сигналит отсутствие расхождения (`up_to_date: true` или
  эквивалент)

### Requirement: синхрон на init/upgrade сохраняется

The system SHALL keep stamping `owl.version = Owl::VERSION` on both
`owl init` and `owl upgrade`.

#### Scenario: upgrade пере-штампует версию

- WHEN выполняется `owl upgrade` на проекте со старой `owl.version`
- THEN после прогона `owl.version` равен текущему `Owl::VERSION`

# Edge cases

- **Self-hosted дрейф (канонический кейс).** В этом репозитории gem
  бампается на каждой задаче без повторного `owl upgrade`, поэтому
  `owl.version` отстаёт. `owl version` обязан показать оба значения и
  пометить расхождение — это фича, а не баг.
- **Legacy-проект без `owl.version`.** Если проект инициализирован до
  штамповки и ключ отсутствует — `config get version` и `owl version`
  возвращают `null`/пустую штампованную версию **без падения**, не
  выдумывая значение.
- **Алиас только на чтение.** `owl config set version X` НЕ должен молча
  писать в `version` мимо `owl.version` (либо проксировать в `owl.version`,
  либо отклонять — решается в design). Запись каноном остаётся `owl.version`.
- **Перекрытие с TASK-0041.** TASK-0041 (`quick`) в тайтле включает «sync
  config version». По решению пользователя **версией полностью владеет
  TASK-0046**; из TASK-0041 пункт про версию исключается (там остаются
  ready/available overlap + clear current pointer on delete). Зафиксировать
  при работе над TASK-0041.
- **`owl --version` vs `owl version`.** Флаг `--version` (gem) остаётся как
  есть; новая команда `version` шире (gem + project-stamped). Не ломать флаг.

# Acceptance criteria

- [ ] `owl config get version --json` возвращает штампованную `owl.version`
  (не `null`); `config get owl.version` даёт то же значение.
- [ ] `owl config show --json` содержит `owl`-блок с `version`.
- [ ] `owl version --json` печатает gem-версию и project-stamped версию и
  сигналит расхождение/совпадение.
- [ ] Legacy-проект без `owl.version`: команды не падают, возвращают
  пустое/`null` корректно.
- [ ] Регресс-тест: `owl init` и `owl upgrade` штампуют `owl.version =
  Owl::VERSION`.
- [ ] `owl --version` (gem) не сломан.
- [ ] `Owl::VERSION` повышен по minor; запись в `CHANGELOG.md` в том же
  коммите.
- [ ] 100% line coverage для затронутых `lib/owl/**/api.rb` сохранено;
  RuboCop чистый по затронутым файлам.
