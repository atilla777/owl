---
status: passed
summary: Удаление текущей задачи чистит current-указатель; ready/available разведены в owl-cli skill; синхронизация owl.version на upgrade подтверждена спецификациями. RuboCop и rspec зелёные.
---

# Summary

Реализованы все три изменения из утверждённого brief TASK-0041:

- **(a) delete чистит current-указатель.** `Owl::Tasks::Internal::Deleter` теперь
  вызывает `Archive::CurrentResetter.reset_if_matches` после удаления каталога
  задачи. Если current-указатель именовал удалённую задачу — `.owl/local/current.yaml`
  удаляется, и `owl task current` отдаёт `no_current_task` вместо `task_not_found`.
  Удаление не-текущей задачи указатель не трогает (resetter сверяет `task_id`).
- **(b) синхронизация версии конфига уже реализована** в коде (`Refresh#stamp_version`,
  коммит 534147e, версия 0.21.x): `owl upgrade` приводит `owl.version` к `Owl::VERSION`,
  а не-`upgrade` команды его не переписывают. В рамках задачи добавлены регрессионные
  спецификации, подтверждающие оба сценария на уровне CLI.
- **(c) разведение ready/available.** В `skills/owl-cli/SKILL.md` (и в материализованной
  копии `.claude/skills/owl-cli/SKILL.md`) задокументировано, когда использовать
  `owl task available` (workflow-dispatchability, dependency-blind) и `owl task ready`
  (dependency-DAG, добавлена в TASK-0026), плюс что `owl next`/`claim --next` берут
  пересечение. Ни одна команда не удалена.

Поднята версия `Owl::VERSION` 0.22.0 → 0.22.1 (patch: фиксы + обратносовместимое
уточнение документации) и добавлена запись в `CHANGELOG.md`.

Затронутые файлы:
- `lib/owl/tasks/internal/deleter.rb` — вызов `CurrentResetter` + require.
- `lib/owl/version.rb` — bump до 0.22.1.
- `CHANGELOG.md` — запись 0.22.1.
- `skills/owl-cli/SKILL.md` + `.claude/skills/owl-cli/SKILL.md` — разведение ready/available.
- `spec/owl/tasks/api_delete_spec.rb` — 2 новых примера (clears / untouched).
- `spec/owl/cli/upgrade_command_spec.rb` — 2 новых примера (upgrade syncs / non-upgrade не трогает).

Правила слоёв (`docs/agents/27`) соблюдены: доступ к `.owl/`/`tasks/` идёт через
внутренние сервисы (`Deleter`, `CurrentResetter`), сырых FS-вызовов к state не добавлено.
`lib/owl/**/api.rb` не изменялся, поэтому правило 100% покрытия api.rb не задействовано.

# Commands

```
bin/owl step start TASK-0041 implement
bundle exec rspec spec/owl/tasks/api_delete_spec.rb
bundle exec rspec spec/owl/cli/upgrade_command_spec.rb spec/owl/upgrade/refresh_spec.rb
bundle exec rspec spec/owl/tasks/api_delete_spec.rb spec/owl/cli/upgrade_command_spec.rb spec/owl/upgrade/refresh_spec.rb spec/owl/tasks/
bundle exec rubocop lib/owl/tasks/internal/deleter.rb lib/owl/version.rb spec/owl/tasks/api_delete_spec.rb spec/owl/cli/upgrade_command_spec.rb
```

# Outcomes

- `spec/owl/tasks/api_delete_spec.rb`: 7 examples, 0 failures (включая новые
  «clears the current pointer when the deleted task is current» и «leaves the
  current pointer untouched when a non-current task is deleted»).
- `spec/owl/cli/upgrade_command_spec.rb` + `spec/owl/upgrade/refresh_spec.rb`:
  12 examples, 0 failures (включая «syncs .owl/config.yaml owl.version to
  Owl::VERSION» и «do not rewrite owl.version in .owl/config.yaml»).
- Сводный прогон затронутых наборов (`spec/owl/tasks/` + upgrade): **238 examples,
  0 failures**.
- RuboCop по изменённым файлам: **4 files inspected, no offenses detected**.

# Not run

- Полный `bundle exec rspec` (весь репозиторий) не запускался — изменения точечные
  и локализованы в delete-пути, upgrade-спеках и документации; прогнаны все
  непосредственно затронутые наборы. По памяти проекта полный прогон даёт «красный»
  exit-код при 0 падениях (известный health-warts), поэтому он ненадёжен как сигнал.

# Failures or blockers

Блокеров нет. Все запущенные проверки зелёные.

# Residual risks

- **Дрейф версии в реальном конфиге.** `.owl/config.yaml` этого репозитория всё ещё
  хранит `owl.version: 0.21.0` — он синхронизируется только при следующем `owl upgrade`
  (по дизайну, чтобы read-команды не мутировали конфиг). Это ожидаемое поведение,
  не дефект.
- **Материализованная копия скилла.** Источник `skills/owl-cli/SKILL.md` и копия
  `.claude/skills/owl-cli/SKILL.md` отредактированы синхронно вручную; повторный
  `bin/owl init --force` регенерирует копию из источника и останется идемпотентным.
