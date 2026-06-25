---
status: approved
summary: "Cleanup в GitRunner после TASK-0032: удалить мёртвые publics status_porcelain/add_all (0 вызовов) и переименовать index_dirty? → index_clean? (сейчас ok=true означает «индекс ПУСТ» — имя читается против шерсти). Чистый рефакторинг, без изменения поведения."
---

# Problem

После TASK-0032 (scoped-staging) в `lib/owl/commit_push/internal/git_runner.rb`
остался технический долг, отмеченный в ревью:

1. **Мёртвые публичные методы.** `status_porcelain` и `add_all` больше нигде не
   вызываются (Transaction перешёл на `add_scoped`/`index_dirty?`). Подтверждено:
   единственное упоминание — в комментарии. Мёртвый код в публичном фасаде runner'а.
2. **Имя `index_dirty?` против шерсти.** Метод возвращает `Outcome.ok == true`,
   когда индекс **ПУСТ** (`git diff --cached --quiet` exit 0), т.е. «не dirty».
   Читать `index_dirty?(...).ok` как «грязный? → да» при пустом индексе —
   контринтуитивно (это заметил ревьюер TASK-0032).

# Goal

Убрать мёртвые `status_porcelain`/`add_all` и переименовать `index_dirty?` в
имя, где `ok == true` читается по смыслу (`index_clean?` — «индекс чист/пуст»),
обновив единственный вызов в Transaction и тесты. Поведение `owl commit-push`
не меняется — чистый рефакторинг.

# Scenarios

### Requirement: мёртвые publics удалены

The system SHALL remove the unused `status_porcelain` and `add_all` methods from
`GitRunner`.

#### Scenario: методы отсутствуют, поведение не меняется
- WHEN после правки прогоняется весь набор тестов commit_push
- THEN `GitRunner` не содержит `status_porcelain`/`add_all`
- AND все тесты commit_push зелёные (никто на них не опирался)

### Requirement: index_dirty? переименован в читаемое имя

The system SHALL rename `index_dirty?` so that `ok == true` matches the method
name's meaning.

#### Scenario: index_clean? с тем же поведением
- WHEN `git diff --cached --quiet` завершается 0 (индекс пуст)
- THEN `GitRunner.index_clean?(root:).ok == true`
- AND Transaction (`index_empty?`/`retry?`/guard) использует новое имя и ведёт себя
  идентично прежнему

# Edge cases

- **Без изменения поведения.** Это рефакторинг: `owl commit-push` стейджит/гейтит/
  ретраит ровно как после TASK-0032. Семантику `Outcome.ok = git success` не трогаем.
- **Тесты.** Обновить `spec/owl/commit_push/git_runner_spec.rb`,
  `api_spec.rb`, `locking_spec.rb`, где встречается `index_dirty?`. Удаляемые методы
  тестов не имеют (проверено) — правок под их удаление не требуется.
- **Публичный API CLI не затронут.** `GitRunner` — internal-фасад; ни CLI-команда,
  ни JSON-контракт не меняются.
- **Версионирование.** Внутренний cleanup без изменения поведения → patch bump
  VERSION + CHANGELOG.

# Acceptance criteria

- [ ] `GitRunner.status_porcelain` и `GitRunner.add_all` удалены.
- [ ] `GitRunner.index_dirty?` → `GitRunner.index_clean?` (та же реализация/семантика
  `ok`); единственный вызов в Transaction и все тесты обновлены.
- [ ] Поведение `owl commit-push` неизменно; весь набор RSpec зелёный, 0 failures;
  100% покрытие `**/api.rb` сохранено.
- [ ] RuboCop net-zero на тронутых файлах; patch bump VERSION + CHANGELOG.
