---
status: approved
summary: "owl version в self-hosted source-репозитории показывает ложный дрейф (gem vs устаревший config owl.version); распознавать self-hosted и считать Owl::VERSION авторитетным (self_hosted: true, up_to_date: true), config не трогать."
---

# Problem

В self-hosted source-репозитории Owl команда `owl version` сообщает ложный
дрейф версии. Сейчас она сравнивает два источника:

- `gem` — константа `Owl::VERSION` (в source-чекауте читается из рабочего
  дерева `lib/owl/version.rb`);
- `project` — стэмп `owl.version` из `.owl/config.yaml`, записываемый только
  при `owl init` / `owl upgrade`.

Реальное наблюдаемое состояние: `{ gem: 1.2.0, project: 1.1.1,
up_to_date: false }`. В потребительском (consumer) проекте такое сравнение
осмысленно — оно сигналит «установлен более новый гем, но не выполнен
`owl upgrade`». Но в самом source-репозитории `Owl::VERSION` и есть
источник истины разрабатываемого гема: его бампают при каждой доставке, тогда
как `owl.version` в config обновляется лишь при прогоне `owl upgrade` на самом
себе. Поэтому config-стэмп закономерно отстаёт, а `owl version` хронически
показывает `up_to_date: false` — ложный сигнал, апгрейдить тут нечего.

Связанная история: `owl.version` как кэш-стэмп и его экспонирование в CLI
введены в TASK-0046; настоящая задача — закрыть порождённый этим self-hosted
edge case.

# Goal

В self-hosted source-репозитории Owl `owl version` НЕ должна показывать ложный
дрейф. Команда должна распознавать, что запущена в собственном source-дереве
Owl, считать `Owl::VERSION` авторитетным значением и для `project`, помечать
результат флагом `self_hosted: true` и возвращать `up_to_date: true`. При этом
никаких побочных записей в `.owl/config.yaml` не выполняется (config остаётся
нетронутым). Поведение в consumer-проектах (где собственного source-дерева Owl
нет) остаётся ровно прежним — полная обратная совместимость.

# Scenarios

### Requirement: Self-hosted detection treats Owl::VERSION as project version

The system SHALL, when `owl version` runs inside the Owl self-hosted source
repository, report the project version from `Owl::VERSION` rather than from the
stamped `owl.version`.

#### Scenario: owl version in source repo with stale config stamp
- WHEN `owl version --json` запускается в корне self-hosted source-репозитория,
  где `Owl::VERSION` = 1.2.0, а `.owl/config.yaml` хранит `owl.version` = 1.1.1
- THEN ответ содержит `gem: "1.2.0"` и `project: "1.2.0"`
- AND `up_to_date: true`
- AND `self_hosted: true`

### Requirement: Self-hosted detection emits a self_hosted flag

The system SHALL include a `self_hosted` boolean in the `owl version` result
that is `true` only when the command is running inside the Owl source
repository.

#### Scenario: consumer project reports self_hosted false
- WHEN `owl version --json` запускается в обычном consumer-проекте (нет
  собственного source-дерева Owl в корне)
- THEN ответ содержит `self_hosted: false`
- AND `project` берётся из стэмпа `owl.version` как прежде

### Requirement: Consumer drift reporting is unchanged

The system SHALL preserve the existing gem-vs-stamp comparison and
`up_to_date` semantics for any project that is not the Owl self-hosted source
repository.

#### Scenario: consumer with newer gem still sees drift
- WHEN `owl version --json` запускается в consumer-проекте, где установленный
  гем (`Owl::VERSION`) новее застэмпленного `owl.version`
- THEN `up_to_date: false` (как и до изменения)
- AND `project` равен застэмпленному `owl.version`, а не `Owl::VERSION`

### Requirement: No config side effects

The system SHALL NOT write to `.owl/config.yaml` (including `owl.version`) as a
side effect of running `owl version`.

#### Scenario: owl version leaves config untouched
- WHEN `owl version` запускается в self-hosted source-репозитории с устаревшим
  `owl.version` в config
- THEN значение `owl.version` в `.owl/config.yaml` остаётся неизменным после
  выполнения команды

# Edge cases

- **Legacy project без стэмпа** (`owl.version` отсутствует, `nil`): в consumer
  поведение прежнее (`project: null`, `up_to_date: false`); если такой проект
  при этом является self-hosted source-репозиторием, срабатывает self-hosted
  ветка и `project` берётся из `Owl::VERSION`.
- **Детектор self-hosted** — механизм распознавания (например, наличие в корне
  `lib/owl/version.rb` плюс gemspec `owl-cli`, либо иной надёжный признак) —
  деталь дизайна; решается на шаге `design`. Критерий: детектор должен
  срабатывать в этом репозитории и НЕ срабатывать в consumer-установках, где
  материализованы только `.owl/` / `tasks/` / `docs/`, но нет `lib/owl/`.
- **Запуск из подкаталога** source-репозитория: детекция должна опираться на
  разрешённый project root, а не на текущую рабочую директорию.
- **Ложноположительная детекция** в consumer-проекте, случайно содержащем файл
  с похожим именем, недопустима — признак выбирается максимально специфичным к
  source-дереву Owl.
- **JSON-контракт**: добавление поля `self_hosted` — аддитивное расширение
  ответа `owl version`; существующие ключи (`gem`, `project`, `up_to_date`) не
  переименовываются и не удаляются.

# Acceptance criteria

- `owl version --json` в этом self-hosted репозитории возвращает
  `{ gem: <Owl::VERSION>, project: <Owl::VERSION>, self_hosted: true,
  up_to_date: true }` независимо от значения `owl.version` в config.
- В consumer-проекте `owl version --json` возвращает `self_hosted: false`,
  `project` равен застэмпленному `owl.version`, а `up_to_date` сохраняет
  прежнюю семантику (drift при расхождении).
- `owl version` не выполняет никаких записей в `.owl/config.yaml`.
- Покрытие: новые/изменённые строки публичного API под `lib/owl/**/api.rb`
  (в частности `lib/owl/version/api.rb`) имеют 100% line coverage в RSpec, с
  отдельными примерами для self-hosted и consumer веток
  (`docs/agents/30_Owl_Ruby_testing_RSpec_and_public_API_coverage.md`).
- Изменение бампает `Owl::VERSION` и добавляет запись в `CHANGELOG.md` в том же
  коммите (минорный бамп — аддитивное поле `self_hosted` + новое поведение).
- Текстовый (не-JSON) вывод `owl version` остаётся осмысленным: в self-hosted
  репозитории он не вводит в заблуждение про дрейф.
