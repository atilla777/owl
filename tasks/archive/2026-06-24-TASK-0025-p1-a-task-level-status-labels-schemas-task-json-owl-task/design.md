---
status: shipped
summary: "Модель данных трекер-метаданных: explicit status (enum), labels[], schemas/task.json, index-carried поля, owl task query/set-status/label CLI."
---

# Context

P1-A — фундамент «Owl как трекер». Нужно расширить модель задачи минимально-инвазивно
и upgrade-safe, переиспользуя locked `IndexWriter` (TASK-0021) и существующий валидатор
(`Owl::Validation`). Последующие P1-B (deps/ready) и P1-C (search) опираются на эти поля.

# Decision

1. **Поле `status` (explicit, task-level).** Хранится в `task.yaml`. Enum:
   `open | in_progress | blocked | on_hold | done | archived`. Семантика —
   **ортогональна step-прогрессу** (ведётся вручную/агентом как трекер-lifecycle, не
   выводится из шагов, чтобы избежать неоднозначности). Дефолт `open` при create.
   `owl archive` системно ставит `archived` (текущее поведение сохраняется). Сеттер:
   `owl task set-status TASK-ID <status>` (валидирует enum).

2. **Поле `labels: []` (массив строк).** Хранится в `task.yaml`. Мутаторы:
   `owl task label add TASK-ID <label>` (идемпотентно, без дублей),
   `owl task label rm TASK-ID <label>`. Нормализация: trim, без пустых.

3. **`schemas/task.json`.** Формальная JSON-схема `task.yaml`: описывает существующие
   поля (id/title/workflow/kind/parent_id/priority/created_at/steps/artifacts) + новые
   (`status` enum, `labels` array<string>). `additionalProperties: true` (не ломать
   будущие/неизвестные поля). Валидация — при мутациях (set-status, label, create) через
   `Owl::Validation` (тот же JSON-schema walker, что для workflow/artifact).

4. **Index расширение.** Записи `tasks/index.yaml` несут `status` и `labels`, чтобы
   `query` работал по индексу без чтения каждого `task.yaml`. `IndexRebuilder`
   извлекает их из `task.yaml`; запись — через locked `IndexWriter`.

5. **`owl task query`.** `owl task query [--status S] [--label L] [--priority N]
   [--parent ID] [--workflow K] [--json]` — комбинируемые **AND**-фильтры по индексу.
   `--label` повторяемый = AND по нескольким меткам (или одиночный в v1; зафиксировать
   одиночный, расширяемо). Вывод — список index-entries (как `task list`, но
   отфильтрованный).

6. **Обратная совместимость (миграция по чтению).** Старые `task.yaml` без новых полей
   читаются как `status: open`, `labels: []`; не форсируем rewrite. `index rebuild`
   проставляет дефолты в индексе. Схема допускает отсутствие полей у legacy (или
   дефолтит при чтении).

# Alternatives

- **Derived status из шагов** (вместо explicit). Отвергнуто: нельзя выразить
  `on_hold`/`blocked` на уровне задачи, и возникает двусмысленность «done по шагам vs
  on_hold вручную». Explicit поле — как у beads/Jira.
- **Query через скан `task.yaml`** (вместо index-carried). Отвергнуто: O(n) чтение
  файлов на каждый запрос; индекс уже материализуется — дешевле фильтровать его.
- **labels как отдельный файл/реестр.** Избыточно; массив в `task.yaml` достаточен и
  локален к задаче.

# Risks

- **Дрейф index ↔ task.yaml.** Митигируется тем, что и create, и мутаторы идут через
  `IndexWriter` (rebuild сканирует task.yaml как источник истины).
- **Сложность схемы / ложные отказы валидации.** `additionalProperties: true` и
  дефолты для legacy-полей снижают риск; покрыть тестами legacy-файлы.
- **Расширение `tasks/api.rb` → требование 100% покрытия.** Все новые ветки покрыть.
- **Семантика `done` vs архив.** Зафиксировать: `done` — логически завершена, но не
  заархивирована; `archived` — перемещена в archive/. Не смешивать.

# API

CLI (JSON-контракт `{ok, value|error}`):
- `owl task set-status TASK-ID <status>` → `{ok, task_id, status}`; ошибка
  `invalid_status` при enum-нарушении.
- `owl task label add|rm TASK-ID <label>` → `{ok, task_id, labels}`.
- `owl task query [--status][--label][--priority][--parent][--workflow] [--json]`
  → `{ok, tasks: [index-entry...]}` (AND-фильтры).
- `owl task list` — без изменений (полный список); query — отфильтрованный.

Ruby (`Owl::Tasks::Api`): `set_status(root:, task_id:, status:)`,
`add_label/remove_label(root:, task_id:, label:)`, `query(root:, filters:)` →
`Owl::Result`. Валидация через `Owl::Validation::Api.json_schema` (или существующий
walker) против `schemas/task.json`. Index-entry билдер (`IndexRebuilder.build_index_entry`)
дополняется `status`/`labels`.
