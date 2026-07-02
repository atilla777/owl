# Goal

Реализовать команду `owl overview [TASK-ID] [--all] [--compact] [--json]`: ASCII-дерево
задач (иерархия, статус, зависимости, текущая) по образцу триплета `workflow_show`,
питаемое существующими `Api`-слоями; вынести дублирующиеся статус-константы в общий
модуль; добавить seed-скилл `/owl-overview` и авто-показ в оркестраторе за
`settings.ui.auto_render_tree`; поднять версию и обновить CHANGELOG.

# Checklist

- [ ] `lib/owl/step_status.rb` — новый общий модуль: `DONE_STATUSES`, `BLOCKING_STATUSES` (task+step), карта маркеров `{done:'[✓]',current:'[▶]',pending:'[ ]',skipped:'[~]',blocked:'[!]'}`, глифы бара `━`/`·`. Значения = точная копия текущих.
- [ ] Переключить на общий модуль (behaviour-preserving, значения не менять): `lib/owl/status/internal/constants.rb`, `lib/owl/cli/internal/commands/workflow_diagram_data.rb`, `lib/owl/cli/internal/commands/workflow_diagram_renderer.rb`, `lib/owl/orchestration/internal/next_action_resolver.rb`.
- [ ] `lib/owl/cli/internal/commands/overview_data.rb` — сборка view-модели: лес из `Owl::Tasks::Api.tree` (весь / поддерево по `TASK-ID`); обогащение каждого узла `progress{done,total,pct}` из `Owl::Status::Api.show`; флаг `current` из `Owl::Tasks::Api.current`; `unmet_deps` из `blocked_by[]` с логикой «терминальная/отсутствующая = выполнена» (как `ready_scanner.deps_complete?`); фильтр терминальных, если не `--all`; прокинуть `warnings` из tree (cycle/depth).
- [ ] `lib/owl/cli/internal/commands/overview_renderer.rb` — ASCII: отступы `├─`/`└─` по вложенности; богатый узел (`marker id title workflow ━━━···· N/M`); компактный узел (`marker id title`); inline `⛔ ждёт TASK-XXXX`; пометка `◀ текущая`; шапка + пустой лес → строка «нет запланированных задач». Ширина заголовка обрезается (напр. до 48 симв. с `…`). Маркеры/бар — из `Owl::StepStatus`.
- [ ] `lib/owl/cli/internal/commands/overview.rb` — команда: разбор `[TASK-ID]`, `--all`, `--compact`, `--json`; неизвестный `TASK-ID` → структурированная ошибка; `--json` → `JsonPrinter` c `{ok,tree,current_task_id,warnings}`; иначе → renderer.
- [ ] `lib/owl/cli/internal/api.rb` — зарегистрировать `overview` в `SIMPLE_COMMANDS`.
- [ ] `lib/owl/cli/internal/help_text.rb` — строка справки для `owl overview`.
- [ ] `skills/owl-overview/SKILL.md` — тонкая обёртка (по образцу `skills/owl-workflow-show`), + регистрация в `owl init` материализации; зеркалировать в оба layout'а.
- [ ] Обновить `skills/owl-orchestrator/SKILL.md`: в шаге старта прогонки и на `handoff_composite` проверять `settings.ui.auto_render_tree` и печатать `bin/owl overview` (по образцу `auto_render_diagram`).
- [ ] Документация: упомянуть `settings.ui.auto_render_tree` там же, где `auto_render_diagram` (README / соответствующий раздел), и `owl overview` в списке команд.
- [ ] `lib/owl/version.rb` — minor-bump; `CHANGELOG.md` — запись.
- [ ] Спеки (см. «Tests and verification»).

# Smoke test

```
bin/owl overview                 # ASCII-лес нетерминальных задач; TASK-0055 помечена ◀ текущая
bin/owl overview TASK-0055       # поддерево одной задачи
bin/owl overview --compact       # сжатые узлы
bin/owl overview --json          # {ok,tree,current_task_id,warnings}
bin/owl overview --all           # включая archived/abandoned
bin/owl overview NONEXISTENT-1   # структурированная ошибка, не трейсбек
bin/owl config set settings.ui.auto_render_tree true   # затем прогон owl-orchestrator печатает обзор один раз
```

# Scope

- Новая CLI-команда `owl overview` (triplet command+data+renderer в `cli/internal/commands`).
- Общий модуль статус-констант + переключение 4 существующих мест на него (behaviour-preserving).
- Новый конфиг-флаг `settings.ui.auto_render_tree` (honored скиллом, дефолт false).
- Seed-скилл `/owl-overview` + правка `owl-orchestrator` SKILL.md.
- Version bump + CHANGELOG + краткая документация команды/флага.

# Constraints

- Доступ к состоянию — только через `Api`-слой (`Tasks::Api`, `Status::Api`), без прямых FS-чтений `.owl/`/`tasks/`/`docs/` (docs/agents/27).
- Не менять контракт `owl task tree` и другие существующие JSON-ответы (аддитивно).
- Рефактор констант строго behaviour-preserving — значения не меняются.
- Переиспользовать словарь маркеров/бар `workflow show` (через общий модуль), не плодить новый.
- Seed-правки зеркалить в оба layout'а; `.claude/` обновлять `owl upgrade`.
- Соблюсти сервис-объектный стиль и RuboCop (docs/agents/28, 29).

# Files to inspect

- `lib/owl/cli/internal/commands/workflow_show.rb`, `workflow_diagram_data.rb`, `workflow_diagram_renderer.rb` — образец триплета и словарь маркеров.
- `lib/owl/cli/internal/commands/task_tree.rb` + `lib/owl/tasks/internal/tree_builder.rb` — источник иерархии, cycle/depth-guard, форма узла.
- `lib/owl/status/internal/builder.rb` + `views.rb` + `constants.rb` — прогресс и статус-константы.
- `lib/owl/tasks/internal/ready_scanner.rb` (`deps_complete?`) — логика «зависимость выполнена».
- `lib/owl/orchestration/internal/next_action_resolver.rb` — 4-е место статус-констант + `current`.
- `lib/owl/cli/internal/api.rb`, `help_text.rb`, `internal/json_printer.rb` — регистрация/справка/JSON.
- `skills/owl-workflow-show/SKILL.md`, `skills/owl-orchestrator/SKILL.md` — образец скилла + точка авто-показа.
- `lib/owl/version.rb`, `CHANGELOG.md`.

# Tests and verification

- `spec/owl/cli/overview_command_spec.rb` — новый: лес (иерархия+отступы), поддерево по `TASK-ID`, `--compact`, `--all`, `--json`-контракт, подсветка текущей, inline-зависимости, пустой лес, неизвестный `TASK-ID` → ошибка, цикл/глубина → warnings. Fixtures с parent/child и `blocked_by`.
- Спеки рендерера/data-builder при необходимости отдельно (по образцу `workflow_diagram_renderer_spec.rb`, `workflow_show_diagram_spec.rb`).
- Прогнать существующие спеки status/orchestration/cli после извлечения констант — должны остаться зелёными (доказательство behaviour-preserving).
- `bundle exec rspec` целиком; `rubocop` по затронутым файлам.
- Smoke-команды из раздела выше на живом репо.
- Если добавятся строки в какой-либо `lib/owl/**/api.rb` — 100% покрытие этих строк (docs/agents/30).

# Out of scope

- SQLite-хранилище, loops/sub-workflow — не трогаем (отложено ранее).
- DAG-стрелки зависимостей / отдельный deps-вид — отклонено в brief.
- Изменение контракта `owl task tree` / `owl status` / прочих команд.
- Интерактивный/цветной TUI, авто-refresh — только статичный ASCII.
- Обобщение `workflow_diagram_renderer` под оба вида — отклонено в design.
