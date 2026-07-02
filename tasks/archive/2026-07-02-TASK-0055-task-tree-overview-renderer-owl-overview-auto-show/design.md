---
status: shipped
summary: Триплет command+data+renderer в cli/internal/commands (по образцу workflow_show), питается существующими Api-слоями (Tasks/Status), общий модуль статус-констант, авто-показ на уровне скилла за settings.ui.auto_render_tree.
---

# Context

Данные для обзора уже существуют в JSON-командах; не хватает только рендерера
(см. `brief`). В репозитории есть один образцовый ASCII-путь — `owl workflow show`,
реализованный триплетом в `lib/owl/cli/internal/commands/`:

- `workflow_show.rb` — команда (разбор аргументов, режимы, `--json`).
- `workflow_diagram_data.rb` — сборка view-модели из `Owl::Workflows::Api`.
- `workflow_diagram_renderer.rb` — ASCII (словарь маркеров `[✓][▶][ ][~][!]`, бар `━`/`·`).

Он не имеет собственного `api.rb` — вся логика cli-internal, покрывается спеками команды.
Наборы статус-констант (done/blocker/маркеры) продублированы в ~4 местах:
`status/internal/constants.rb`, `cli/.../workflow_diagram_data.rb`,
`cli/.../workflow_diagram_renderer.rb`, `orchestration/internal/next_action_resolver.rb`.

Источники, из которых будет питаться обзор (всё — через слой `Api`, без прямых FS-чтений):

- Иерархия: `Owl::Tasks::Api.tree` (бэкенд `tasks/internal/tree_builder.rb`) — вложенный лес `{id,title,workflow_key,kind,status,parent_id,children[]}` + cycle/depth-guard.
- Прогресс/шаги/блокеры/дети: `Owl::Status::Api.show` (бэкенд `status/internal/builder.rb`) — `progress{done,total,pct}`.
- Зависимости: поле `blocked_by[]` из индекса (через `Owl::Tasks::Api`), «выполнена ли зависимость» — та же логика, что `ready_scanner.deps_complete?` (терминальная/отсутствующая = выполнена).
- Текущая задача: `Owl::Tasks::Api.current` (указатель `.owl/local/current.yaml`).

# Decision

**1. Структура кода — зеркалим триплет `workflow_show`** в `lib/owl/cli/internal/commands/`:

- `overview.rb` — команда `owl overview [TASK-ID] [--all] [--compact] [--json]`; разбирает флаги, вызывает data-builder, затем renderer (ASCII) либо `JsonPrinter` (`--json`).
- `overview_data.rb` — собирает view-модель: берёт лес из `Tasks::Api.tree` (весь / поддерево по `TASK-ID`), обогащает каждый узел прогрессом из `Status::Api.show`, флагом `current` из `Tasks::Api.current`, и `unmet_deps` из `blocked_by[]`. Фильтрует терминальные, если не `--all`.
- `overview_renderer.rb` — рисует ASCII-дерево: отступы `├─`/`└─` по вложенности, per-node строка (богато/компактно), inline `⛔ ждёт TASK-XXXX`, пометка `◀ текущая`.

Логики бизнес-уровня, требующей нового `lib/owl/**/api.rb`, не вводим — обзор
оркеструет уже существующие `Api`-вызовы на cli-уровне (как `workflow_show`). Значит
правило «100% покрытия `api.rb`» затрагивает нас только если добавим строки в
существующие `api.rb` (не планируется); новая cli-логика покрывается спеками команды.

**2. Регистрация** — добавить `overview` в `SIMPLE_COMMANDS` (`cli/internal/api.rb`) и
строку в `help_text.rb`.

**3. Общий модуль статус-констант** — вынести дублирующиеся наборы в один модуль
(напр. `lib/owl/step_status.rb`: `DONE_STATUSES`, `BLOCKING_STATUSES`, карта
маркеров). Все 4 текущих места ссылаются на него. Строго behaviour-preserving —
значения не меняются, существующие спеки зелёные.

**4. Авто-показ — на уровне скилла, не в Ruby.** По образцу существующего
`settings.ui.auto_render_diagram`: `owl-orchestrator` в начале прогонки и на
`handoff_composite` проверяет `owl config get settings.ui.auto_render_tree` и, если
`true`, печатает вывод `bin/owl overview`. CLI-гейта не добавляем — так меньше
связанности и симметрично уже принятому паттерну. Дефолт — не задан/`false` (молчит).

**5. JSON-контракт** (`--json`) — обогащённый лес, суперсет узла `task tree`:
`{ok, tree:[node], current_task_id, warnings[]}`, где node =
`{id,title,workflow_key,kind,status,parent_id, progress:{done,total,pct}, current:bool, blocked_by:[...], unmet_deps:[...], children:[...]}`. Аддитивно к `task tree` — его контракт не трогаем.

**6. Seed-скилл `/owl-overview`** — тонкая обёртка (по образцу `owl-workflow-show`),
материализуется `owl init`. Правки seed зеркалятся в оба layout'а
(`workflows/`/`skills/` исходники и `.owl/`), `.claude/` обновляется `owl upgrade`.

**7. Версия** — minor-bump `Owl::VERSION` + запись в `CHANGELOG.md` (новая команда,
новый флаг конфига, новый seed-скилл; обратносовместимо).

# Alternatives

- **Расширить `owl task tree --ascii` вместо новой команды.** Отклонено: `task tree` —
  чистый структурный дамп (стабильный контракт), обзор — обогащённое представление
  (прогресс/текущая/зависимости). Смешивать назначения — размыть оба; отдельная
  команда `owl overview` (решение brief) чище.
- **Обобщить `workflow_diagram_renderer` под оба вида.** Отклонено: он step-ориентирован
  (плоский список шагов одной задачи), а обзор — иерархия задач; разные домены,
  обобщение раздует один рендерер. Разделяем рендереры, но **делим словарь маркеров**
  через общий модуль (решение №3).
- **Триггерить авто-показ из `owl next` (хинт `render_tree`).** Отклонено: конфиг-проверка
  на уровне скилла симметрична `auto_render_diagram` и не связывает движок `next` с UI.
- **Зависимости стрелками DAG / отдельным видом.** Отклонено в brief (inline-аннотация).

# Risks

- **Перф: N сборок статуса** (по одной `Status::Api.show` на задачу для прогресс-бара).
  Митигируется фильтром «только нетерминальные по умолчанию» (малое N) и отсутствием
  тяжёлых вычислений; при `--all` на большом архиве — приемлемая деградация, при
  необходимости прогресс для архивных можно не считать.
- **Рефактор статус-констант затрагивает status/orchestration/cli.** Риск тонкого
  сдвига поведения. Митигация: строго behaviour-preserving извлечение (те же
  значения), опора на существующие спеки этих модулей + прогон полного RSpec.
- **Широкие строки в терминале.** Митигация: `--compact` + обрезка заголовка до
  разумной ширины (описать точную ширину в plan).
- **Unicode box-drawing/маркеры** в отдельных терминалах — приемлемо, `workflow show`
  уже использует `✓ ▶ ━`.
- **Покрытие спеками** новой cli-логики — покрыть команду/data/renderer напрямую
  (fixtures с иерархией, зависимостями, текущей, пустым лесом, циклом).

# API

Публичная поверхность, публикуемая в `docs/` при `merge_docs`:

- **CLI:** `owl overview [TASK-ID] [--all] [--compact] [--json]`
  - без `TASK-ID` — весь лес нетерминальных задач; с `TASK-ID` — его поддерево;
  - `--all` — включить `archived`/`abandoned`; `--compact` — сжатый узел; `--json` — структурный вывод.
  - Exit: `0` успех; структурированная ошибка (не трейсбек) при неизвестном `TASK-ID`.
- **JSON-схема ответа** (`--json`): `{ok:true, tree:[node], current_task_id, warnings:[...]}`
  с node-полями `{id,title,workflow_key,kind,status,parent_id,progress{done,total,pct},current,blocked_by,unmet_deps,children}`.
- **Config:** `settings.ui.auto_render_tree` (boolean, дефолт false) — авто-показ обзора
  в `owl-orchestrator` (старт прогонки + `handoff_composite`).
- **Skill:** `/owl-overview` — тонкая обёртка над `owl overview`.
- **Внутренний общий модуль:** `Owl::StepStatus` (или аналог) — единый источник
  статус-констант/маркеров для status/orchestration/cli (внутренний, не публичный CLI-контракт).
