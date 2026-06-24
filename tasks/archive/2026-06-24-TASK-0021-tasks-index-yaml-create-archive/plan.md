# Goal

Сериализовать все мутации `tasks/index.yaml` через repo-scoped `Owl::Locks` лок
(`name: "index"`), чтобы конкурентные create/archive/delete/rebuild из разных сессий
не приводили к потерянным обновлениям ростера.

# Scope

- Обернуть scan+write индекса (`IndexRebuilder.rebuild` и любые прямые мутаторы
  ростера) в захват/освобождение индекс-лока через `Owl::Locks`.
- TTL + гарантированное освобождение (`ensure`).
- Регрессионный тест на сериализацию.
- Bump `Owl::VERSION` (patch) + CHANGELOG.

# Constraints

- Индекс собирается ПОЛНЫМ сканом task-dir (`IndexRebuilder.rebuild` →
  `AtomicYamlWriter.write`), а не read-modify-write. Поэтому корректность достигается
  тем, что scan+write выполняется под локом целиком (каждая пересборка атомарна
  относительно других).
- Использовать существующий `Owl::Locks::Api.acquire(root:, name:, ttl:, token:)` /
  `release(root:, name:, token:)` — НЕ изобретать новый лок-механизм
  (`lib/owl/locks/api.rb`).
- Лок берётся в самой узкой точке, общей для всех писателей индекса, чтобы не
  дедлочиться с уже удерживаемыми per-task lease/step-локами. Предпочтительно —
  централизовать запись индекса в одном внутреннем хелпере и лочить там.
- Атомарный write+rename сохраняется как есть; лок добавляется ВОКРУГ него.
- Освобождение в `ensure`, TTL по умолчанию (консистентно с прочими локами);
  упавшая сессия не должна заклинивать ростер.

# Checklist

1. Найти все точки записи `tasks/index.yaml`: `IndexRebuilder.rebuild`,
   `archive/orchestrator.rb`, `deleter.rb`, создатель задач (id_generator/creator),
   set-priority, child create — пройти по вызывающим `IndexRebuilder`/`AtomicYamlWriter`
   на `index_path`.
2. Ввести единый внутренний путь записи индекса (хелпер/метод), который:
   `Owl::Locks.acquire(root:, name: "index", ttl: <default>)` → выполнить
   scan+write → `release` в `ensure`. Перенаправить всех писателей через него.
3. Прокинуть `root` (repo root) туда, где сейчас есть только `tasks_root`/`index_path`
   (лок-бэкенд кладёт лок-файл под `local_state` role; нужен root).
4. Тест сериализации: либо юнит на сам locked-writer (захват лока виден второму
   вызову как занятый/сериализуется), либо интеграционный — две операции create
   подряд под общим локом дают индекс с обеими записями. Проверить отсутствие
   самоблокировки в одиночной цепочке create→archive.
5. 100% покрытие затронутых `lib/owl/**/api.rb` (если меняется `tasks/api.rb`).
6. Bump `Owl::VERSION` (patch) + `CHANGELOG.md`.

# Files to inspect

- `lib/owl/tasks/internal/index_rebuilder.rb` — основная точка scan+write.
- `lib/owl/tasks/internal/atomic_yaml_writer.rb` — атомарная запись (не трогать механику).
- `lib/owl/tasks/internal/archive/orchestrator.rb`, `deleter.rb`, создатель задач,
  set-priority — прочие писатели ростера.
- `lib/owl/locks/api.rb`, `lib/owl/locks/backends/filesystem.rb`,
  `lib/owl/locks/internal/file_lock.rb` — лок-механизм (переиспользовать).
- `lib/owl/tasks/api.rb` — публичный фасад, прокинуть `root` при необходимости.
- `lib/owl/storage/*` — резолв `local_state` role для лок-файла.
- `spec/owl/tasks/`, `spec/owl/locks/` — тесты.

# Tests and verification

- Регрессионный тест на сериализацию записи индекса под локом (обе записи сохраняются;
  нет самоблокировки одиночной сессии).
- `bundle exec rspec` зелёный (после — `git checkout README.md`).
- 100% покрытие затронутых `**/api.rb`; RuboCop net-zero на трогаемых файлах.

# Smoke test

```
# В тестовом репо: запустить два create «одновременно» (или последовательно под локом)
owl task create --workflow feature --title A
owl task create --workflow feature --title B
owl task list --json   # → обе задачи присутствуют, индекс консистентен
owl task index rebuild --json   # идемпотентно, без зависаний
```

# Out of scope

- SQLite-бэкенд / инкрементальный индекс (P3).
- Безопасный scoped-staging `owl commit-push` (отдельная находка из TASK-0020).
- PF-фиксы CLI (TASK-0022..0024).
