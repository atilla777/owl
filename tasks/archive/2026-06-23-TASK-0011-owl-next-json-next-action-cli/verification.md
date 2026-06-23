---
status: passed
summary: Реализована read-only команда `owl next` (домен Owl::Orchestration) + дедуп резолв-ладдера; новые и регрессионные специи зелёные, RuboCop чист, версия 0.2.0.
---

# Summary

Реализован чеклист плана TASK-0011 полностью. Добавлена read-only команда
верхнего уровня `owl next [TASK-ID] --json` через новый домен
`Owl::Orchestration`: `NextActionResolver` композирует существующие
Tasks/Workflows API и возвращает дискриминированный `action.kind ∈
{dispatch_step, handoff_composite, stop_blocked, done, no_available_task}` —
все исходы с exit 0, без мутаций. Дублирующий резолв-ладдер «current pointer»
вынесен в общий примитив `Tasks::Api.current_task_id`, переиспользуемый
`Instructions`/`Status`/`Orchestration` (поведенчески нейтрально). Проза
лестницы в `skills/owl-orchestrator` (§1, §4 + Notes) ужата до вызова
`owl next` с диспетчем по `action.kind`; `skills/owl-cli` документирует команду
и форму ответа. Версия поднята до `0.2.0` (minor) с записью в `CHANGELOG.md`;
`.claude/` перематериализован через `bin/owl upgrade`.

Полный прогон RSpec зелёный (1628 примеров, 0 падений, 1 pending). Покрытие
затронутых `lib/owl/**/api.rb` (`orchestration/api.rb`, `tasks/api.rb`) = 100%
линий в полном прогоне. RuboCop по всем изменённым файлам — без замечаний.
Дымовые вызовы `owl next --json` и `owl next TASK-0011 --json` возвращают
валидный JSON с exit 0.

# Commands

```
bin/owl step start TASK-0011 implement
bundle exec rspec spec/owl/cli/next_spec.rb spec/owl/cli/task_commands_spec.rb \
  spec/owl/cli/internal/commands/lease_commands_spec.rb \
  spec/owl/cli/instructions_spec.rb spec/owl/cli/status_spec.rb \
  spec/owl/skills/seeded_sources_spec.rb spec/owl/cli/init_skills_spec.rb
bundle exec rspec                       # полный прогон
bundle exec rubocop <12 изменённых файлов>
bin/owl upgrade                         # перематериализация .claude/
bin/owl next --json
bin/owl next TASK-0011 --json
bin/owl artifact validate TASK-0011 verification --json
```

# Outcomes

- **Целевой набор специй (back-compat + skills): 138 примеров, 0 падений.**
  Примечание: план брифа ссылался на `spec/owl/cli/ready_steps_spec.rb` и
  `spec/owl/cli/task_available_spec.rb`, которых в репозитории нет — реальные
  CLI-гарды для `task ready-steps`/`task available` живут в
  `spec/owl/cli/task_commands_spec.rb` и
  `spec/owl/cli/internal/commands/lease_commands_spec.rb`; их и прогнал.
- **Полный `bundle exec rspec`: 1628 примеров, 0 падений, 1 pending, exit 0.**
- **RuboCop:** 12 изменённых файлов, 0 замечаний (после авто-исправления
  избыточных `rubocop:disable` в новой специи).
- **Покрытие:** ни `orchestration/api.rb`, ни `tasks/api.rb` не попали в список
  «ниже 100%» в полном прогоне → оба фасада на 100% линий (правило `30_*`).
- **Дымовой тест:** `owl next --json` → `action.kind: stop_blocked`,
  `source: current_pointer`, exit 0 (текущая задача TASK-0011 имеет шаг
  `implement` в статусе `running` — это сам исполняемый шаг, исход корректен);
  `owl next TASK-0011 --json` → `source: explicit`, exit 0; `owl --help`
  перечисляет `next`.
- `next_spec.rb` покрывает все сценарии брифа: авто-выбор (`dispatch_step`,
  `source: auto_select`, без мутаций), приоритет явного `TASK-ID`, резолв из
  current pointer, идемпотентность/read-only, `no_available_task` (exit 0),
  `done`, `stop_blocked`, `handoff_composite`, edge `needs_adopt`.

# Not run

- Сборка/установка гема и `owl upgrade` в consumer-проектах (re/Rrrog, tetris) —
  по контракту шага не выполняются (распространение делает отдельный
  релиз-шаг после merge).
- `owl step complete` и git commit/push — намеренно оставлены оркестратору
  (запрещено контрактом execution-шага).

# Failures or blockers

Блокеров нет. Единственное расхождение с планом — несуществующие имена
спец-файлов в чеклисте (см. Outcomes), разрешено подстановкой фактических
back-compat-гардов; обе команды (`task available`, `task ready-steps`)
JSON-контракты сохранили.

# Residual risks

- `action.kind` становится публичным контрактом: расширять только аддитивно
  (новый kind = minor, удаление/переименование = major).
- `needs_adopt` срабатывает строго при `running`-шаге + присутствующем истёкшем
  lease; `running` без lease (нормальный одно-сессионный кейс) флаг не ставит —
  по дизайну, но это компромисс, который стоит держать в уме при ревью.
- Кросс-доменное использование общего примитива вынесено в `Tasks::Api`
  (низкий слой), что избегает инверсии слоёв; `Orchestration::Internal::TaskResolver`
  добавляет авто-выбор поверх него.
