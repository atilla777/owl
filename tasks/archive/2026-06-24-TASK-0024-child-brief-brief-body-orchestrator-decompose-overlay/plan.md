# Goal

Добавить `owl task child create --brief-body -` (тело child-brief из stdin) и обновить
skill/overlay/decompose-доки: убрать scratch `tasks/<PARENT>/.briefs/`, зафиксировать
запрет parallel зависимых owl-команд, cleanup review-running, запрет пересекающихся
scope в decompose.

# Scope

- FF5 (код): `lib/owl/cli/internal/commands/task_child_create.rb` (+ child_creator) —
  флаг `--brief-body -` (stdin), взаимоисключение с `--brief PATH`.
- FF6 (доки): `workflows/composite_feature/decompose.context.md` (+ `.owl/` копия),
  `skills/_owl_conventions.md`, `skills/owl-step-execution`, `skills/owl-orchestrator`,
  review overlay.
- Тесты + bump `Owl::VERSION` (minor) + CHANGELOG.

# Constraints

- `--brief-body -` следует существующему соглашению `--body -` = stdin (как
  `workflow context set`, `artifact-type template set`). `-` обязателен явно.
- Обратная совместимость: `--brief PATH` и поведение без brief не меняются;
  определить взаимоисключение `--brief` vs `--brief-body` (ошибка при обоих).
- Переданное тело проходит обычную валидацию артефакта; невалидное → понятная ошибка,
  не молчаливое создание.
- Если меняется `lib/owl/**/api.rb` — 100% покрытие.
- Доки FF6 — изменения seed `skills/**` и `workflows/**`: bump VERSION + CHANGELOG;
  после правки `skills/owl-*` рекомендуется `bin/owl upgrade` для `.claude/` (отметить
  в follow-ups, не обязательно в коммите).
- Синхронизировать `.owl/workflows/composite_feature/decompose.context.md` с
  корневым seed (как делалось в TASK-0020).

# Checklist

1. **FF5 CLI.** В `task_child_create.rb`:
   - добавить опцию `--brief-body PATH_OR_DASH` (или булев `--brief-body` + чтение
     stdin при `-`); при `-` читать stdin; интегрировать в существующий
     `load_brief_body` (расширить, чтобы принимал источник «stdin»).
   - валидировать взаимоисключение с `--brief`; обновить usage-строку и `--help`.
   - прокинуть тело в `child_creator` (тот же путь, что `--brief`), brief-артефакт
     пишется по resolved-пути, шаг brief → done (как сейчас для `--brief`).
2. **FF6 decompose.** В `workflows/composite_feature/decompose.context.md`:
   заменить строку `--brief tasks/<PARENT-ID>/.briefs/<slice-slug>.md` на поток
   `--brief-body -` (heredoc/stdin); удалить указание писать в `.briefs/`; добавить
   требование непересекающихся файловых scope детей ДО review (чеклист). Синхронить
   `.owl/` копию.
3. **FF6 parallel-дисциплина.** В `skills/_owl_conventions.md` (и/или
   `skills/owl-step-execution`): явное правило — НЕ запускать parallel зависимые
   owl-команды (мутатор→читатель, особенно `step start`→`step show`); выполнять
   последовательно.
4. **FF6 review cleanup.** В `skills/owl-orchestrator` и/или review overlay
   (`.owl/overlays/review_code.md`): описать, что вердикт `changes_required` оставляет
   шаг `running` и требует `owl step reset <TASK> review_code` перед повторным прогоном.
5. Тесты: `--brief-body -` создаёт child с валидным brief из stdin; взаимоисключение с
   `--brief` даёт ошибку; невалидное тело → ошибка.
6. Bump `Owl::VERSION` (minor) + `CHANGELOG.md`.

# Files to inspect

- `lib/owl/cli/internal/commands/task_child_create.rb` — опции/`load_brief_body`.
- `lib/owl/tasks/internal/child_creator.rb` — приём тела brief.
- `workflows/composite_feature/decompose.context.md` + `.owl/workflows/.../decompose.context.md`.
- `skills/_owl_conventions.md`, `skills/owl-step-execution/SKILL.md`,
  `skills/owl-orchestrator/SKILL.md`, `.owl/overlays/review_code.md`.
- `spec/owl/cli/task_child_create_spec.rb`, `spec/owl/tasks/child_creator_spec.rb`.
- `lib/owl/version.rb`, `CHANGELOG.md`.

# Tests and verification

- Юнит/CLI: `--brief-body -` (stdin) создаёт child + валидный brief; `--brief` +
  `--brief-body` одновременно → ошибка; невалидное тело → понятная ошибка.
- `bundle exec rspec` зелёный (после — `git checkout README.md`).
- 100% покрытие затронутых `**/api.rb`; RuboCop net-zero на трогаемых файлах.

# Smoke test

```
printf '%s\n' '---' 'status: approved' 'summary: x' '---' '# Problem' ... \
  | owl task child create --parent PARENT --workflow feature --title T --brief-body - --json
# → child создан, brief: done, без файла в tasks/<PARENT>/.briefs/
owl task child create --parent P --workflow feature --title T --brief a.md --brief-body - --json
# → ошибка взаимоисключения
```

# Out of scope

- Авто-reset review при changes_required в коде (здесь только документная фиксация).
- Scoped-staging `owl commit-push` (backlog-находка).
