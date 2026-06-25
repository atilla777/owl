---
status: shipped
summary: "В Deleter.call обернуть ровно FileUtils.rm_rf(task_dir) в TaskMutationLock.with_lock(root:, task_id:); clean_dangling_refs + IndexWriter.rebuild остаются ПОСЛЕ и ВНЕ этого лока. task_not_found-проверка до лока. with_lock возвращает err при lock_held — пробросить."
---

# Context

`Deleter.call`: resolve paths → guard task_dir exists → `FileUtils.rm_rf(task_dir)`
→ `clean_dangling_refs` (берёт `task-<child>` лок per зависимая задача) →
`IndexWriter.rebuild` (лок `index`) → `ClaimResetter`. Сам `rm_rf` идёт без
`task-<id>` лока удаляемой задачи (TASK-0035 добавил лок всем writer'ам, но не delete).

# Decision

Обернуть **только** `FileUtils.rm_rf(task_dir)` в
`TaskMutationLock.with_lock(root: root, task_id: task_id) { FileUtils.rm_rf(...) }`:

```
guard exists (task_not_found) — ДО лока
lock_result = TaskMutationLock.with_lock(root:, task_id:) { FileUtils.rm_rf(task_dir.to_s) }
return lock_result if lock_result.err?      # lock_held за дедлайном → recoverable
clean_dangling_refs(...)                     # вне lock(deleted): child-locks по одной
IndexWriter.rebuild(...)                     # index-lock, после
ClaimResetter.delete_if_present(...)
Result.ok(...)
```

Ключевое: `clean_dangling_refs` и `IndexWriter.rebuild` остаются ПОСЛЕ блока и ВНЕ
лока удаляемой задачи. Это сохраняет инвариант «никакой task-lock не удерживается во
время взятия другого task-lock / index-lock» → нет lock-ordering deadlock между
параллельными delete.

`with_lock` возвращает либо err лока, либо значение блока (`rm_rf` возвращает массив
удалённых путей — не Result; обернуть так, чтобы наружу шёл lock-err или продолжение).
Проще: `with_lock` блок просто делает `rm_rf` (side-effect), а `with_lock` вернёт
результат блока; проверяем `lock_result.err?` (Result от acquire-фейла) — если блок
выполнился, `with_lock` вернёт значение блока (не Result) → трактовать как успех.
Чтобы единообразно: блок возвращает `Result.ok`, тогда `with_lock` вернёт его; либо
проверять `lock_result.respond_to?(:err?) && lock_result.err?`. Выбрать чистый вариант
(напр. блок возвращает `Result.ok(:removed)`).

# Alternatives

- **Обернуть весь `call` (включая clean_dangling_refs) в lock(deleted).** Вложенность
  `lock(deleted) → lock(child)` → lock-ordering deadlock между двумя delete (A: X→Y,
  B: Y→X). Отклонено — оборачиваем только rm_rf.
- **Не брать лок вообще (статус-кво).** Оставляет delete-while-in-use хазард.
  Отклонено.
- **Глобальный лок на delete.** Сериализует несвязанные delete без нужды. Отклонено —
  per-task лок удаляемой задачи.

# Risks

- **Возврат значения блока.** `with_lock` возвращает результат блока, а `rm_rf`
  возвращает не-Result. Сделать блок возвращающим `Result.ok`, чтобы
  `lock_result.err?` был корректен и для acquire-фейла, и для успеха. Покрыть тестом.
- **lock_held пробрасывается как ошибка delete.** Поведение: delete не сносит каталог,
  пока жив писатель. Документировать; recoverable. Тест на проброс.
- **Покрытие.** `deleter.rb` — internal; `tasks/api.rb#delete` уже покрыт. Регрессия +
  новый concurrency-тест.

# API

- **CLI/JSON:** `owl task delete` без изменений контракта (может вернуть recoverable
  `lock_held` при живом писателе — как прочие мутаторы).
- **Ruby:** `Deleter.call` оборачивает `rm_rf` в `TaskMutationLock.with_lock`.
  `clean_dangling_refs`/`scrub` — без изменений (уже под child-локами из TASK-0035).
