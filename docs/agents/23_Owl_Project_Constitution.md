# Owl Project Constitution

Imported sources:

- `AGENTS.md` (durable project intent extracted, not full text)
- `ARCHITECTURE.md` (high-level architecture invariants)
- `REQUIREMENTS.md` (general requirements 1–11)

Imported by: `kos-project-memory-import`
Migration role: Project Constitution — required bootstrap article for every agent before normal work.

---

# Owl — Project Constitution

## 1. Назначение проекта

Owl — персональный инструмент для управления AI-assisted разработкой по принципу SDD/spec-driven, но с гибкой системой workflow. Owl управляет workflow, задачами, артефактами, состоянием и публикацией доменных знаний проекта. Owl v1 — персональный инструмент без СУБД, файлового состояния достаточно для MVP, но архитектура должна позволять заменить файловое хранилище на SQLite/БД/remote backend без переписывания skills.

## 2. Source of truth (иерархия)

После подключения KOS:

1. **KOS application state** — авторитетный источник задач, workflow-статуса, спецификаций, планов, артефактов, review-отчётов, completion-отчётов, git-trace. Все workflow-решения проходят через KOS API (`/kos-orchestrator`, `/kos-api`).
2. **KOS knowledge articles** — авторитетные правила, решения, инварианты, нюансы. Этот Constitution article обязательно загружается перед нормальной работой (`load_policy: required`, `required_project_bootstrap: true`).
3. **`docs/`** (в репозитории) — source of truth доменных знаний проекта Owl: опубликованные спецификации после завершения workflow.
4. **`tasks/<TASK-ID>/specs/...`** — proposed spec delta для конкретной активной задачи. Становится частью `docs/` через шаг `publish`.
5. **`.owl/`** — control plane Owl: конфиг проекта, реестр workflow, схемы, реестр артефактов, шаблоны, JSON Schema.
6. **Исторические файлы (`AGENTS_BKP*.md`, исходные `AGENTS.md` / `ARCHITECTURE.md` / `REQUIREMENTS.md` / `IMPLEMENTATION_PLAN.md`)** — только историческая справка. Не использовать как активное состояние workflow.

## 3. Workflow-политика

- Разные типы задач имеют разные workflow (`feature`, `composite_feature`, `feature_slice`, `hotfix`, `research`, `refactor`, `migration`, `bugfix`). Каждый workflow описывается декларативно YAML-схемой.
- Workflow описывает граф шагов и артефактов, а не плоский список.
- Артефакт — центральная единица результата. Типы артефактов переиспользуются между workflow.
- Состояние задачи хранится отдельно от workflow-схемы.
- Шаги могут иметь `may_create_tasks: true` — это явное разрешение порождать child tasks.
- Сложные задачи декомпозируются на child tasks; child tasks хранятся **плоско** в `tasks/`, связь parent → child через `parent_id`, а не через вложенность папок.
- Три уровня декомпозиции (не путать): composite task → child task → `tasks.md` checklist (implementation steps внутри одной задачи).
- Текущая задача определяется по приоритету: явный task id → самая приоритетная → самая старая. Одновременно может быть несколько активных задач (не одна глобальная переменная).

## 4. Качественные ворота

- Workflow должен валидироваться через CLI (`owl config validate --json`) до начала исполнения.
- Артефакты валидируются по JSON Schema и обязательным секциям, определённым в `.owl/artifacts/<type>/artifact.yaml`.
- Шаги имеют явную `failure policy`.
- Шаг `verify` обязателен в большинстве workflow; для composite tasks выполняется `aggregate_verify`.
- Skills не угадывают пути, текущую задачу, статус workflow — всё через Owl CLI.

## 5. Архитектурные инварианты

1. `.owl` — control plane; `tasks` — рабочая зона задач (плоско, parent/child вперемешку); `docs` — source of truth доменных знаний.
2. Не использовать `spec`/`specs` в корне Rails-проекта (конфликт с RSpec).
3. Workflow хранится отдельно для каждого типа задач (`.owl/workflows/<type>/workflow.yaml`).
4. Переиспользуемые типы артефактов описываются отдельно (`.owl/artifacts/<type>/artifact.yaml`).
5. Skills используют CLI, а не читают состояние напрямую.
6. Физические пути задаются через **storage roles** и **конфигурируются через `.owl/config.yaml`** (секция `settings.storage.roles:` с парами `role_name: path`). Workflow не знает физических путей `tasks/` или `docs/`. Тип backend также конфигурируется (`settings.storage.backend`, для v1 — `filesystem`). Это позволяет в будущем заменить файловый backend без изменения workflow и skills.
7. `tasks/index.yaml` — производный индекс (пересобирается из `task.yaml`-файлов через `owl task index rebuild`).
8. `.owl/local/current.yaml` — локальный указатель на текущую задачу/сессию, **не коммитится**.
9. CLI — единый machine API для агентов и skills.

## 5.10. Ruby-код Owl организуется по доменам

Каждый домен — отдельный namespace под `Owl::*` (`Owl::Config`, `Owl::Workflows`,
`Owl::Artifacts`, `Owl::Tasks`, `Owl::Storage`, `Owl::Steps`, `Owl::Validation`,
`Owl::Cli`). Межсекционные взаимодействия идут **только** через публичный фасад
домена — `Owl::<Domain>::Api`. Бизнес-логика — в single-action service классах
под `Owl::<Domain>::Internal::*`. CLI — тонкий адаптер без бизнес-логики.

Возвраты публичного API оформляются через `Owl::Result::Ok` / `Owl::Result::Err`
(stdlib `Data.define`).

Зависимости — stdlib. `dry-rb`, `interactor`, `trailblazer` и аналоги
запрещены без явного согласования.

Детальные правила: knowledge articles *Owl Ruby code architecture* и
*Owl Ruby service objects and OOP*.

## 5.11. Backend abstraction

Owl Storage / Tasks / Workflows работают через backend interface (`Owl::Tasks::Backend`,
`Owl::Storage::Backend`). Filesystem — одна из реализаций. Skills и публичный
`bin/owl` CLI **никогда** не делают backend-specific операций (no `File.read`,
no SQL, no third-party API). Замена backend'а — изолированное изменение,
не затрагивающее skills и CLI surface.

Это расширение существующего инварианта 5.6 (storage roles): тот фиксирует
абстракцию *физических путей*, 5.11 — абстракцию *всего слоя storage*,
включая чтение/запись/архивирование/индексацию.

## 5.12. Step execution model

Один универсальный skill `owl-step-run` исполняет любой шаг любого workflow.
Специализация per-step живёт в **данных**, а не в коде:

- step config в `workflow.yaml` (id, status, requires, creates);
- опциональный `.context.md` файл рядом с `workflow.yaml` (или inline `context:`
  поле в step) — instructions / prompt для агента, выполняющего шаг.

Новые типы шагов **не требуют новых skills** — достаточно описать step
в `workflow.yaml` и приложить `.context.md`.

## 5.13. Skill layering

Owl skills организованы в три слоя:

- **`owl-cli`** — low-level wrapper над `bin/owl` (по аналогии с `kos-api`
  для KOS). Единственный путь skill'а к CLI.
- **`owl-step-run` / `owl-orchestrator`** — reasoning skills; используют
  `owl-cli`, **не** работают со storage напрямую.
- **`bin/owl`** (CLI) — единственный путь к storage / задачам / артефактам /
  workflow state.

Никакой skill не обращается к файлам `.owl/`, `tasks/`, `docs/` напрямую.

## 5.14. Context model

Контекст агента разделён по уровням:

- **Project-level context** (конституция проекта, durable rules, invariants)
  загружается агентом из его harness-specific источника. Owl не специфицирует
  и не управляет этим уровнем — каждый агент (Claude Code, Codex, opencode
  и т.п.) использует свой механизм project-context.
- **Step-specific context** — `.context.md` файлы рядом с `workflow.yaml`;
  путь указан в step через `context_file:` либо inline через `context:`.
  Это *delta* поверх harness project-context, не его замена.
- **Task / step data** (текущий статус, артефакты, prerequisites, blockers) —
  исключительно через `owl step show` / `owl status` / `owl task tree`.
- **Owl runtime settings** — см. 5.17.

## 5.15. Owl CLI as the only state interface

Всё состояние workflow / задач / артефактов авторитативно доступно только
через `bin/owl` CLI. Файлы в `tasks/`, `.owl/`, `docs/` — implementation
detail filesystem backend'а; при другом backend они отсутствуют либо имеют
иной формат. Skills и пользователи Owl **никогда** не парсят эти файлы напрямую.

Это пункт 5.5 в расширенной форме: 5.5 фиксирует требование к skills,
5.15 — экспансия на любого пользователя Owl (включая людей-операторов).

## 5.16. Skill and template language policy

`SKILL.md` файлы skills (Owl и зависимостей) и определения шаблонов
артефактов (`required_sections`, `frontmatter_schema`, placeholder
`template.body`) пишутся на **English** — это canonical contract.
Обоснование: парсимость, harness-агностичность, lingua franca инструментов.

Контент артефактов (то, что агент пишет в body шаблона), user-facing reports
(stop reports, completion reports, blockers, progress updates) и опубликованные
`docs/` материалы — на **языке из `settings.language.*`** (см. 5.17).

`required_sections` (литералные заголовки артефактов) — всегда English,
т.к. они часть schema identity и проходят byte-for-byte validation.

## 5.17. Runtime settings as context layer

К трём уровням контекста из 5.14 добавляется четвёртый — **Owl runtime
settings**:

4. **Owl runtime settings** — конфигурация проекта из `.owl/config.yaml`
   (секция `settings:`). Возвращается через `owl step show` и `owl config show`.
   Минимальный набор:

   - `settings.language.communication` (обязательно) — язык user-facing reports
     skill'а; e.g. `ru`, `en`.
   - `settings.language.artifacts` (optional, default = `communication`) —
     язык контента артефактов.
   - `settings.language.docs` (optional, default = `communication`) — язык
     материалов в `docs/`.
   - `settings.storage.backend` — тип backend; для v1 = `filesystem`.
   - `settings.storage.roles.<role_name>` — путь storage role (см. 5.6).

Каждый Owl skill **обязан**:

- читать `settings.language.*` из ответа CLI (`owl step show` или
  `owl config show`);
- генерировать user-facing reports на `settings.language.communication`;
- заполнять артефакты на `settings.language.artifacts` (или
  `communication`, если не задан);
- писать `docs/` контент на `settings.language.docs` (или
  `communication`, если не задан).

Inheritance даёт минимальный конфиг для типичного случая
(только `communication: ru`) при сохранении гибкости для смешанных
(например `communication: ru`, `docs: en`).

## 6. Knowledge-capture duties

- Когда работа выявляет повторяемую project-specific ловушку, API-поведение, workflow-нюанс, или другой урок — это durable знание, а не приватная память.
- Классифицируется taxonomy `kind: nuance` с подходящими `scope` и `topic` тегами из `kos-api.list_tags`.
- Не изобретать новые теги в закрытых группах (`kind`, `scope`, `topic`). Группа `subtopic` — открытая, можно создавать новые значения через `subtopic:` при write.
- Перед записью знания: `kos-api.check_knowledge_conflicts`, затем `create_knowledge_entry` или `update_knowledge_entry`.

## 7. Repository handoff и git-политика

- Commit + push выполняются автоматически, когда нет нерешённых вопросов, провалов проверок, подозрительных файлов, секретов, размытого scope или сомнений в destination.
- Если есть сомнения — остановиться и спросить человека.
- Финальный git-trace фиксируется через `kos-api.finalize_task_git_trace`.
- Завершение задачи фиксируется отдельно — `completion_report` артефакт + transition в done.

## 7.1. Версионирование и дистрибуция гема (non-negotiable)

Owl распространяется как гем `owl-cli`. Проекты-потребители (`re`/Rrrog,
`tetris`, новые проекты) вызывают **установленный гем** на PATH, а не этот
checkout — это отдельная копия. Поэтому изменение в коде Owl доходит до них
только через пересборку гема, и версия — сигнал дистрибуции.

Правило: **любое изменение, которое меняет поведение или материализуемое
потребителями содержимое, ОБЯЗАНО в том же коммите/PR поднять
`Owl::VERSION` и добавить запись в `CHANGELOG.md`.**

- В scope (триггерит бамп) — изменения в путях из `spec.files` гемспека,
  затрагивающие runtime или seed-контент: `lib/**/*.rb`, `bin/owl`,
  `skills/**`, `commands/**`, `workflows/**`, `artifacts/**`,
  `schemas/**/*.json`.
- Вне scope (бамп не требуется) — изменения, не меняющие поставляемое
  поведение/контент: `spec/**`, `docs/**` (кроме `README.md`),
  служебные правки `.owl/` этого репо, комментарии.
- SemVer: `patch` — фиксы и обратносовместимые добавления; `minor` —
  новые возможности; `major` — ломающие изменения (формат на диске,
  публичный CLI/JSON-контракт, `required_sections`).
- Почему обязательно: `owl upgrade` решает, что заменять, побайтовым
  сравнением (версия-агностично), но переустановка гема поверх той же
  версии неоднозначна (нужен `--force`, потребитель не отличит старое от
  нового). Без бампа корректное обновление потребителей невозможно.
- После бампа — пайплайн распространения: `git push` → `gem build
  owl-cli.gemspec && gem install` → `owl upgrade` в каждом
  проекте-потребителе (он сохраняет их `.owl/config.yaml` и `docs/ai/*`
  overlays). После правок в `skills/owl-*` также обнови `.claude/`/
  `.opencode/` этого репо через `bin/owl upgrade`.

## 8. Stop conditions

Останавливаться и звать человека при:

- KOS API недоступен;
- отсутствии actor identity (`KOS_USER_ID`) для мутирующих API-операций;
- проваленных проверках, которые выходят за scope текущей задачи;
- подозрительных файлах, потенциальных секретах;
- размытом scope или конфликте версий после reload;
- неоднозначном destination для push;
- расхождении между durable знаниями (этим Constitution + связанными rule/decision/invariant articles) и наблюдаемым состоянием — сначала верифицировать, обновить устаревшее знание, и только потом продолжать.

## 9. Источники

- Полный концептуальный документ: knowledge article `Owl product concept: AGENTS.md` (kind=decision, scope=project_local, topic=workflow, subtopic=concept).
- Полная архитектура: knowledge article `Owl architecture: ARCHITECTURE.md` (kind=decision, scope=project_local, topic=service, subtopic=architecture).
- Полные функциональные требования: knowledge article `Owl requirements: REQUIREMENTS.md` (kind=rule, scope=project_local, topic=workflow, subtopic=requirements).
- Этапный план реализации (`IMPLEMENTATION_PLAN.md`) **не импортирован** — это staged roadmap; в KOS он должен жить как иерархия задач, а не как knowledge article.

