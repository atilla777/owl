---
status: shipped
summary: "GitRunner: add_scoped(exclude) через git pathspec :(exclude) + index_dirty?(git diff --cached). Transaction.call(exclude:) прокидывает в оба add; guard/retry переведены с clean_tree?(весь tree) на index-состояние. Api.commit_push вычисляет exclude = активные(Tasks::Api) - текущая → tasks/<id>."
---

# Context

`owl commit-push` стейджит `git add -A` (`GitRunner#add_all`), вызываемый дважды
в `Transaction` (`stage_and_guard` до лока; `flip_done` под локом, чтобы flip
`commit_push: done` попал в тот же коммит). Guard пустой-доставки и retry-ветка
опираются на `clean_tree?` = `git status --porcelain` пуст (весь рабочий tree).
При со-существующем backlog (`?? tasks/TASK-*`) tree никогда не пуст → ломаются
оба инварианта, а сами backlog-файлы попадают в коммит.

# Decision

## 1. GitRunner — scoped staging + index-проверка
- `add_scoped(root:, exclude: [])`: при пустом `exclude` — текущее `git add -A`
  (back-compat). Иначе magic-pathspec:
  `git add -A -- . :(exclude)tasks/<id1> :(exclude)tasks/<id2> …`.
  (`add_all` оставить или выразить через `add_scoped(exclude: [])` — на выбор
  имплементатора; сохранить публичный метод, если на него опираются тесты.)
- `index_dirty?(root:)`: `git diff --cached --quiet` → `Outcome.ok == true`, когда
  exit 0 (индекс ПУСТ). Удобный предикат «есть ли что-то застейджено»:
  трактуем `index_dirty?(root:).ok` как «индекс чист». (Назвать так, чтобы смысл
  Outcome.ok совпал с остальным runner'ом: `ok == git-success`; `git diff
  --cached --quiet` success ⇒ нет staged.)

## 2. Transaction — exclude + инварианты в терминах индекса
- `call(root:, task_id:, step_id:, message:, git:, locks:, steps:, exclude: [])`.
- `stage_and_guard`: `git.add_scoped(root:, exclude:)`; затем «если индекс пуст
  (`index_dirty?.ok`) → `nothing_to_commit`». Больше НЕ использовать
  `status_porcelain`/`clean_tree?` для guard.
- `flip_done`: `git.add_scoped(root:, exclude:)` (вместо `add_all`).
- `retry?`: `step_done? && index_empty? && unpushed?`, где `index_empty?` —
  `git.index_dirty?(root:).ok` (индекс чист). Заменяет `clean_tree?`. Семантика:
  «шаг done, коммит уже создан (нечего стейджить), есть неотправленный коммит» →
  повтор только pull+push. Неотслеженный backlog больше не влияет.
- Удалить теперь неиспользуемый `clean_tree?` (или оставить только если ещё нужен).

## 3. Api.commit_push — вычисление exclude
- `Api.commit_push(root:, task_id:, …)` перед вызовом `Transaction.call`
  собирает `exclude`:
  - активные задачи через `Owl::Tasks::Api.list(root:)` (читает индекс — активные,
    без архива);
  - отфильтровать `id == task_id` (текущую НЕ исключаем);
  - смэппить в относительные пути `"tasks/#{id}"`.
- Передать `exclude:` в `Transaction.call`. Доступ к активным — через Tasks::Api
  (слой соблюдён, без прямого FS из commit_push).
- Граничные: пустой список/ошибка чтения → `exclude = []` (фолбэк на прежнее
  поведение, не падать на staging).

# Alternatives

- **Не трогать guard/retry, только scoped-add.** Неотслеженный backlog оставляет
  `status --porcelain` непустым → `nothing_to_commit` не ловит пустую доставку, а
  `retry?` никогда не истинен (ломает идемпотентность при backlog). Отклонено —
  фикс был бы半-готовым.
- **Fail-fast: отказывать commit-push при наличии чужих незакоммиченных задач.**
  Безопасно, но неудобно (пользователь хочет, чтобы команда просто работала при
  backlog). Отклонено в пользу scoped-staging.
- **Исключать ВСЕ `tasks/TASK-*` верхнего уровня.** Сломало бы quick-доставку
  (нет шага archive → текущая задача ещё в `tasks/<task_id>/` и была бы исключена).
  Поэтому исключаем активные **минус текущая**.
- **Снимок/whitelist путей доставки.** Изменения кода произвольны, надёжно
  привязать их к задаче нельзя. Поэтому чёрный список чужих task-каталогов, а не
  белый список.

# Risks

- **Семантика retry ослабляется** с «весь tree чист» до «индекс пуст». Корректно
  для scoped-staging и для существующих сценариев без backlog (после успешного
  commit индекс пуст). Покрыть тестами retry с и без backlog.
- **Регрессия существующих тестов транзакции** (`api_spec`/`locking_spec`): fake_git
  использует `add_all`/`status_porcelain`. Обновить fake_git: добавить
  `add_scoped`, `index_dirty?`; заменить ожидания `add_all`-twice на
  `add_scoped`-twice; `status_porcelain('')`-clean → `index_dirty?` ok-ветки.
- **pathspec-экранирование.** id задач — `TASK-\d+`, спецсимволов нет; `:(exclude)`
  безопасен. Передавать как отдельные argv-элементы (без шелла) — уже так
  (`Open3.capture3(*cmd)`).
- **Покрытие api.rb.** `commit_push/api.rb` расширяется (вычисление exclude) —
  держать 100% (ветки: есть активные/нет/ошибка чтения).

# API

- **CLI:** `owl commit-push` без новых флагов; поведение staging — scoped.
- **Ruby:**
  - `GitRunner.add_scoped(root:, exclude: [])`, `GitRunner.index_dirty?(root:)`
    (новые); `add_all` сохраняется при необходимости.
  - `Transaction.call(..., exclude: [])`; guard/retry в терминах индекса.
  - `CommitPush::Api.commit_push` — вычисляет exclude через `Owl::Tasks::Api.list`,
    фильтрует текущую, мапит в `tasks/<id>`.
