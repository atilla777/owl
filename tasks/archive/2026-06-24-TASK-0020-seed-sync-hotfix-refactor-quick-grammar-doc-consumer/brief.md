---
status: approved
summary: "Промотировать hotfix/refactor/quick workflows и Requirement/Scenario grammar-doc в gem-сид, чтобы свежий owl init/upgrade в consumer-проекте получал все 5 workflow и рабочую ссылку на грамматику."
---

# Problem

В этом репозитории все 5 workflow (`feature`, `composite_feature`, `hotfix`,
`refactor`, `quick`) валидны и грузятся, потому что живут в догфуд-копии
`.owl/workflows/`. Но в **gem-дистрибутив** они не попадают:

- `owl-cli.gemspec` пакует `workflows/**/*` от корня репозитория, а там лежат
  только `feature` и `composite_feature` (`ls workflows/` подтверждает).
- Реестр по умолчанию (`lib/owl/workflows/internal/default_template.rb`) тоже
  регистрирует только эти два.
- Итог: свежий `owl init` в новом проекте даёт 2 workflow, а не 5;
  `hotfix`/`refactor`/`quick` де-факто «локальный догфуд», а не продукт.

Параллельно brief-артефакт ссылается на
`docs/agents/31_Owl_Requirement_Scenario_grammar.md` для Requirement/Scenario
грамматики. Этот файл существует в репо Owl, но **не сидится в consumer-проект**,
поэтому в потребителе (наблюдалось в `re`) ссылка битая, а агент не может понять
требуемый формат `#### Scenario:` / `- WHEN` / `- THEN`.

# Goal

Сделать так, чтобы любой consumer, поставивший gem и выполнивший `owl init`
(или `owl upgrade`), получал **все заявленные в реестре workflow** и **рабочую
ссылку на Requirement/Scenario грамматику** — без расхождения между догфуд-копией
`.owl/` и тем, что реально доставляется через gem.

# Scenarios

### Requirement: Свежая установка получает все зарегистрированные workflow

#### Scenario: owl init в новом проекте материализует hotfix/refactor/quick
- WHEN пользователь ставит gem `owl-cli` и выполняет `owl init` в пустом проекте
- THEN `owl workflow list --json` возвращает `feature`, `composite_feature`,
  `hotfix`, `refactor`, `quick`, и для каждого `source_present: true`

#### Scenario: реестр по умолчанию согласован с поставляемыми сидами
- WHEN сид-механизм формирует стартовый `.owl/workflows.yaml`
- THEN каждый зарегистрированный ключ имеет существующий `source:`-файл в сборке,
  и нет записи реестра без соответствующего workflow.yaml

### Requirement: Грамматика Requirement/Scenario доступна в consumer-проекте

#### Scenario: ссылка на грамматику из brief-артефакта разрешается в потребителе
- WHEN агент в consumer-проекте открывает brief-артефакт и идёт по ссылке на
  Requirement/Scenario грамматику
- THEN документ грамматики присутствует в проекте после `owl init`/`owl upgrade`
  (либо его текст встроен в артефакт), и ссылка не битая

# Edge cases

- **Идемпотентность upgrade.** Повторный `owl upgrade` не должен затирать
  пользовательские кастомизации (`managed:false`) и overlay-файлы; промотируемые
  workflow помечены `managed:true` и обновляются по правилам провенанса.
- **Решение по `quick`.** В текущем реестре `quick` помечен `managed:false`.
  Нужно осознанно выбрать: сделать его `managed:true` сидом или оставить как
  пример — без «зарегистрирован, но не доставляется».
- **Расхождение grammar-doc.** Если выбираем доставку файла, его содержимое в
  gem-сиде должно совпадать с каноном в репо Owl (не должно отставать, как уже
  бывало с context.md).
- **Версионирование.** Изменение сидов/реестра/gemspec — consumer-visible, значит
  bump `Owl::VERSION` + запись в `CHANGELOG.md` в том же коммите (Constitution §7.1).

# Acceptance criteria

- [ ] Корневой `workflows/` сид содержит `hotfix/`, `refactor/`, `quick/`
  (workflow.yaml + их context-файлы), и `gem build` включает их.
- [ ] `default_template.rb` (реестр по умолчанию) регистрирует все 5 workflow с
  существующими `source:`-путями; принято явное решение по `quick`
  (`managed:true` сид либо удаление из реестра).
- [ ] Requirement/Scenario грамматика доступна в consumer: файл сидится
  `owl init`/`owl upgrade` **или** ссылка в brief-артефакте заменена на
  самодостаточный встроенный текст.
- [ ] Верификация: `gem build owl-cli.gemspec` → `owl init` во временном проекте →
  `owl workflow list --json` показывает 5 с `source_present:true`; ссылка на
  грамматику в новом проекте разрешается.
- [ ] `Owl::VERSION` поднят и добавлена запись в `CHANGELOG.md`.
- [ ] Затронутые `lib/owl/**/api.rb` (если есть) сохраняют 100% покрытие; RuboCop
  net-zero на трогаемых файлах.
