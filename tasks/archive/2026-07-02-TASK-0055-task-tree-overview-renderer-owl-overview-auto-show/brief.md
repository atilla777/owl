---
status: approved
summary: Новая команда `owl overview` рисует ASCII-дерево задач (иерархия, статус, зависимости, текущая) + опциональный авто-показ в оркестраторе за конфиг-флагом.
---

# Problem

У пользователя Owl нет краткого наглядного представления о том, что запланировано:
как задачи вложены друг в друга (composite parent → children), в каком они статусе,
какие между ними зависимости (`blocked_by`) и какая задача сейчас текущая. Данные
для этого уже есть в JSON-командах (`owl task tree`, `owl status`,
`owl task aggregate-status`, `owl next`, поле `blocked_by[]` в `tasks/index.yaml`),
но во всём проекте есть ровно один ASCII-рендерер — `owl workflow show TASK-ID`, и он
рисует лишь плоский список шагов **одной** задачи. Дерева задач с иерархией,
зависимостями, статусами и подсветкой текущей — нет. Пользователь вынужден собирать
картину в голове из нескольких JSON-выводов.

# Goal

Дать псевдографическое (ASCII) представление плана задач — иерархию, статус каждой
задачи, зависимости и текущую задачу — единым, читаемым в терминале видом,
согласованным с уже существующим словарём маркеров `owl workflow show`. Показывать
его по явному запросу всегда, и автоматически в осмысленных точках оркестратора за
конфиг-флагом. Рендерер только читает уже существующие JSON-источники — новой модели
данных не вводим.

# Scenarios

### Requirement: Обзор всего леса задач

The system SHALL render, on `owl overview` with no task id, an ASCII tree of all
non-terminal tasks grouped by `parent_id`, each node showing its status marker, id,
title and (rich mode) workflow, progress bar and step count.

#### Scenario: Плоский и вложенный лес
- WHEN пользователь выполняет `owl overview` без аргумента и в проекте есть открытые задачи, часть из которых — дети composite-родителей
- THEN выводится ASCII-дерево, где дети отрисованы с отступом под своим родителем (`├─`/`└─`)
- AND каждый узел несёт маркер статуса (`[✓]`/`[▶]`/`[ ]`/`[~]`/`[!]`), id и заголовок
- AND терминальные задачи (`archived`/`abandoned`) по умолчанию скрыты

### Requirement: Обзор поддерева одной задачи

The system SHALL render, on `owl overview TASK-ID`, only that task's subtree
(the task and its descendants).

#### Scenario: Поддерево composite-задачи
- WHEN пользователь выполняет `owl overview TASK-0050`, где у TASK-0050 есть дети
- THEN выводится дерево с корнем TASK-0050 и его детьми, без прочих задач проекта

### Requirement: Подсветка текущей задачи

The system SHALL mark the current task (from the current pointer / `owl next`)
distinctly in the rendered tree.

#### Scenario: Отметка текущей
- WHEN среди отрисованных задач есть текущая (указатель `.owl/local/current.yaml`)
- THEN её строка помечена явным индикатором текущей (например `◀ текущая`) в дополнение к маркеру статуса

### Requirement: Отображение зависимостей

The system SHALL annotate each task that has unmet `blocked_by` dependencies with an
inline marker naming the blocking task(s).

#### Scenario: Задача ждёт зависимость
- WHEN у задачи в `blocked_by[]` есть задача, ещё не находящаяся в терминальном статусе
- THEN строка задачи получает inline-аннотацию вида `⛔ ждёт TASK-XXXX`
- AND зависимости НЕ рисуются стрелками произвольного DAG (только inline-текст)

### Requirement: Богатая детализация узла

The system SHALL, in the default (rich) mode, show per node the status marker, id,
title, workflow key, a progress bar and the done/total step count.

#### Scenario: Богатый узел
- WHEN задача отрисована в режиме по умолчанию
- THEN её строка содержит маркер, id, заголовок, ключ workflow, прогресс-бар (`━`/`·`) и счётчик шагов `N/M`

#### Scenario: Компактный режим
- WHEN пользователь передаёт `--compact`
- THEN узел сокращается до маркера, id, заголовка и пометки текущей/блокировки (без бара и workflow)

### Requirement: Включение терминальных задач по флагу

The system SHALL include archived/abandoned tasks in the output only when `--all`
is passed.

#### Scenario: Показать всё
- WHEN пользователь выполняет `owl overview --all`
- THEN в дерево включаются и терминальные задачи (`archived`/`abandoned`)

### Requirement: Машиночитаемый вывод

The system SHALL support `--json` on `owl overview`, returning the structured tree
data instead of ASCII, consistent with the CLI's JSON-by-default convention.

#### Scenario: JSON-вывод
- WHEN пользователь выполняет `owl overview --json`
- THEN команда возвращает структурированный JSON (дерево + статус + зависимости), а не ASCII

### Requirement: Авто-показ в оркестраторе за конфигом

The system SHALL auto-render the overview at the start of an `owl-orchestrator`
drive and on an `action.kind == handoff_composite`, only when
`settings.ui.auto_render_tree` is `true`.

#### Scenario: Флаг включён
- WHEN `settings.ui.auto_render_tree == true` и оркестратор начинает прогонку задачи или получает `handoff_composite`
- THEN обзор дерева печатается пользователю один раз в этой точке
- AND обзор НЕ печатается на каждом шаге (пошаговый вид покрыт `owl workflow show`)

#### Scenario: Флаг выключен или не задан
- WHEN `settings.ui.auto_render_tree` не задан или `false`
- THEN авто-показ не происходит; обзор доступен только по явному запросу

### Requirement: Согласованность словаря маркеров

The system SHALL reuse the existing marker vocabulary and progress-bar glyphs of
`owl workflow show` rather than introducing a divergent set.

#### Scenario: Единый вид
- WHEN обзор отрисован
- THEN маркеры статуса и символы прогресс-бара совпадают с теми, что использует `owl workflow show`

# Edge cases

- **Пустой проект** — нет нетерминальных задач: вывести короткое «нет запланированных задач», не пустую строку и не ошибку.
- **Цикл / слишком глубокая вложенность в `parent_id`** — переиспользовать защиту `tree_builder` (cycle-guard + предел глубины), показать предупреждение, не зациклиться.
- **Зависимость на несуществующую/уже архивную задачу** — трактовать как выполненную (как `ready_scanner.deps_complete?`), не показывать `⛔`.
- **Битый указатель текущей** (текущая задача удалена/архивна) — рендерить без подсветки текущей, не падать.
- **Очень широкая строка** — `--compact` как ручной выход; переносы/обрезку заголовка описать в дизайне.
- **`owl overview NONEXISTENT-ID`** — структурированная ошибка, не трейсбек.
- **Многосессионность** — обзор read-only, не берёт lease и не мутирует состояние; согласован с параллельными сессиями.

# Acceptance criteria

- `owl overview` без аргумента рисует ASCII-лес нетерминальных задач с иерархией, статусом, зависимостями и подсветкой текущей.
- `owl overview TASK-ID` рисует поддерево этой задачи.
- `--all`, `--compact`, `--json` работают согласно сценариям.
- Зависимости показаны inline (`⛔ ждёт TASK-XXXX`), без DAG-стрелок.
- Авто-показ работает в старте прогонки оркестратора и на `handoff_composite` только при `settings.ui.auto_render_tree == true`; иначе — молчит.
- Рендерер переиспользует словарь маркеров/бар `owl workflow show`; дублирующиеся наборы статус-констант сведены в один общий модуль (behaviour-preserving).
- Новый seed-скилл `/owl-overview` (тонкая обёртка над CLI) материализуется `owl init`; правки seed-контента зеркалятся в оба layout'а (`workflows/` и `.owl/workflows/`), `.claude/` обновляется через `owl upgrade`.
- Публичный API-код (`lib/owl/**/api.rb`), затронутый задачей, покрыт спеками на 100% строк (RSpec).
- Доступ к состоянию — только через слой `bin/owl`/Backend, без прямых FS-чтений `.owl/`/`tasks/`/`docs/` (см. `docs/agents/27_...`).
- `Owl::VERSION` поднят (minor) и добавлена запись в `CHANGELOG.md` в том же коммите.
- Изменение back-compat: новая команда + новый флаг конфига + новый seed-скилл; существующие JSON-контракты и managed-определения не ломаются.
