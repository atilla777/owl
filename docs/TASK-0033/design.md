---
status: shipped
summary: "Удалить GitRunner.status_porcelain/add_all (мёртвые). Переименовать index_dirty? → index_clean? (та же реализация). Обновить 1 вызов в Transaction + 3 спека. patch bump. Поведение неизменно."
---

# Context

`lib/owl/commit_push/internal/git_runner.rb` после TASK-0032 содержит мёртвые
`status_porcelain` (был для `clean_tree?`) и `add_all` (заменён `add_scoped`).
`index_dirty?(root:)` = `git diff --cached --quiet`; `Outcome.ok == true` при
ПУСТОМ индексе — имя контринтуитивно. Единственный вызов — в Transaction
(`index_empty?` хелпер, стр.135). Тесты ссылаются на `index_dirty?` в
`git_runner_spec.rb`, `api_spec.rb`, `locking_spec.rb`; на удаляемые методы тестов
нет.

# Decision

1. **Удалить `status_porcelain` и `add_all`** из GitRunner (мёртвый код). Убрать
   упоминание `add_all` в комментарии `add_scoped` (переформулировать на «empty
   exclude → `git add -A`»).
2. **Переименовать `index_dirty?` → `index_clean?`**, сохранив реализацию
   (`git diff --cached --quiet`) и семантику `Outcome.ok = git success` (ok ⇔ индекс
   чист/пуст). Имя теперь читается по смыслу: `index_clean?(...).ok == true` ⇒ чисто.
3. **Обновить вызов в Transaction**: `index_empty?` helper зовёт
   `git.index_clean?(root:).ok` (имя helper'а `index_empty?` оставить — локально
   ясно: «индекс пуст»; связка index_empty? = git.index_clean?.ok).
4. **Обновить тесты**: заменить ключ `index_dirty?` на `index_clean?` в fake_git
   (`api_spec`, `locking_spec`) и описания/вызовы в `git_runner_spec`; смысл
   значений не меняется (ok ⇒ пусто, fail ⇒ есть staged).

# Alternatives

- **Оставить мёртвые методы «на будущее».** Накопление мусора в публичном фасаде;
  ревью TASK-0032 явно пометило их как cleanup. Отклонено.
- **Имя `index_empty?` для git-метода вместо `index_clean?`.** Оба читаются верно;
  `index_clean?` ближе к git-словарю («clean working tree/index») и не конфликтует с
  существующим transaction-хелпером `index_empty?`. Выбрал `index_clean?`.
- **Инвертировать семантику (`ok` ⇒ dirty).** Сломало бы общий контракт runner'а
  `Outcome.ok = git success`. Отклонено — меняем только имя.

# Risks

- **Пропустить упоминание `index_dirty?`.** Митигировано grep-проверкой по lib/+spec/
  после правки (0 вхождений).
- **Случайно изменить поведение.** Реализация index_clean? = байт-в-байт прежний
  index_dirty?; удаляемые методы не вызывались. Весь набор rspec — регрессионный
  контроль.

# API

- **CLI/JSON:** без изменений.
- **Ruby (internal):** `GitRunner.status_porcelain`, `GitRunner.add_all` удалены;
  `GitRunner.index_dirty?` → `GitRunner.index_clean?` (та же сигнатура/семантика).
  Transaction зовёт новое имя. Публичный API гема не затронут.
