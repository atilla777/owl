# Goal

Реализовать три CLI-UX фикса: (1) subcommand-help для групп команд, (2) hint про
`owl task adopt` в `claim --steal` на running-шаге, (3) re-read состояния в выводе
`task child create --brief`.

# Scope

- `lib/owl/cli/api.rb` (диспетчер групп) + `lib/owl/cli/internal/help_text.rb` —
  subcommand-help (FF1).
- `lib/owl/tasks/api.rb` claim / `lib/owl/tasks/internal/claim_service.rb` — hint про
  adopt (FF3).
- child-create команда — re-read состояния после prefill brief (FF4).
- Тесты + bump `Owl::VERSION` (minor) + CHANGELOG.

# Constraints

- **`lib/owl/cli/api.rb` подпадает под 100% покрытие `lib/owl/**/api.rb`** — любые
  новые ветки в нём обязаны быть покрыты тестами. То же для `lib/owl/tasks/api.rb`.
- Не ломать `owl --help` и существующий формат вывода групповых команд.
- Неизвестная подкоманда (`owl step bogus`) по-прежнему `unknown_command` с прежним
  exit-кодом; help (`owl step`, `owl step --help`) → exit 0.
- Hint в `claim --steal` — дополнительное поле в JSON + строка в человекочитаемом
  выводе; НЕ менять успех/exit и логику claim (только информировать).
- FF3: новой логики takeover не вводим — `owl task adopt` уже существует; добавляем
  только подсказку. Сверить, что `owl next` уже отдаёт `needs_adopt` (есть) — выводы
  согласованы.

# Checklist

1. **FF1 subcommand-help.** В диспетчере групп (`cli/api.rb`, где сейчас зовётся
   `unknown_command` для пустой/`--help` подкоманды) распознать случай «группа без
   подкоманды» и «группа + `--help`/`-h`» и печатать список подкоманд группы из
   `help_text.rb` (расширить его реестром подкоманд по группам). Применить к `step`,
   `task`, `workflow`, `artifact` (и по возможности единообразно ко всем группам).
   Exit 0. JSON-режим — структурированный список подкоманд.
2. **FF3 takeover hint.** В пути `task claim --steal` (claim_service): если у задачи
   есть шаг в статусе `running`, добавить в успешный ответ поле `hint` /
   `running_step` с текстом «step '<id>' is running; run `owl task adopt <TASK-ID>` to
   take it over». Прокинуть в человекочитаемый вывод.
3. **FF4 child-create re-read.** В команде `task child create` после prefill brief
   перечитать состояние задачи (через тот же путь, что `owl status`/inspect) перед
   сборкой JSON-вывода, чтобы шаг отражал `brief: done`.
4. Тесты: (a) `owl step`/`owl step --help` → список подкоманд, exit 0; `owl step
   bogus` → unknown_command; (b) claim --steal на running-шаге → hint присутствует;
   (c) child create --brief → вывод показывает `brief: done`.
5. Покрыть новые ветки в `cli/api.rb`/`tasks/api.rb` до 100%.
6. Bump `Owl::VERSION` (minor) + `CHANGELOG.md`.

# Files to inspect

- `lib/owl/cli/api.rb` — диспетчер групп, точки `unknown_command`.
- `lib/owl/cli/internal/help_text.rb` — тексты help (расширить реестром подкоманд).
- `lib/owl/cli/internal/commands/` — групповые команды (`task_*`, `step_*`, child create).
- `lib/owl/tasks/api.rb`, `lib/owl/tasks/internal/claim_service.rb` — claim/steal + статус шагов.
- `lib/owl/tasks/internal/` — child create / brief prefill путь.
- `spec/owl/cli/**`, `spec/owl/tasks/**` — тесты.
- `lib/owl/version.rb`, `CHANGELOG.md`.

# Tests and verification

- Юнит/CLI-тесты на три сценария (см. checklist 4).
- `bundle exec rspec` зелёный (после — `git checkout README.md`).
- 100% покрытие `cli/api.rb` и `tasks/api.rb` в полном прогоне; RuboCop net-zero на
  трогаемых файлах.

# Smoke test

```
owl step            # → список подкоманд step, exit 0
owl step --help     # → то же
owl task --help     # → список подкоманд task
owl step bogus      # → unknown_command (как раньше)
# на задаче с running-шагом:
owl task claim TASK-ID --steal --json   # → ответ содержит hint про owl task adopt
owl task child create --parent P --workflow feature --title T --brief … --json
                    # → JSON показывает brief: done
```

# Out of scope

- `--brief-body -` (stdin тело brief) и overlay-доки — TASK-0024.
- Изменение логики adopt/takeover (только hint).
