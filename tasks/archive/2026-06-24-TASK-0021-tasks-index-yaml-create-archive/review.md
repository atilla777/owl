---
status: resolved
summary: "Все писатели tasks/index.yaml сериализованы под leaf-локом `index` через IndexWriter; retry с ограниченным дедлайном, TTL-авто-реклейм, error-path с rollback в archive; rspec 1793/0, rubocop net-zero, VERSION 0.8.1 + CHANGELOG. Дефектов не найдено."
verdict: accepted
ready: true
---

# Summary

Изменение сериализует все мутации `tasks/index.yaml` под repo-scoped именованным
локом `Owl::Locks` (`index`). Введён единый locked-write путь
`Owl::Tasks::Internal::IndexWriter`, через который маршрутизированы ВСЕ писатели
ростера. `IndexRebuilder.rebuild` остаётся чистым scan+atomic-write; лок берётся
вокруг него.

Проверено независимо:
- **Единая точка записи.** grep по `lib/`: единственный вызывающий
  `IndexRebuilder.rebuild` теперь `IndexWriter` (`index_writer.rb:45`). Все шесть
  писателей ростера маршрутизированы через `IndexWriter.rebuild`:
  - create → `lib/owl/tasks/backends/filesystem.rb:101`
  - index rebuild → `filesystem.rb:272`
  - set-priority/write_priority → `filesystem.rb:367`
  - delete → `lib/owl/tasks/internal/deleter.rb:32`
  - abandon → `lib/owl/tasks/internal/abandon_writer.rb:46`
  - archive → `lib/owl/tasks/internal/archive/mover.rb:79`
  Прямых записей индекса через `AtomicYamlWriter` мимо `IndexRebuilder` нет; все
  прочие касания `index_path` — это чтения (`IndexReader`) или проброс пути.
- **Leaf-лок без дедлоков.** `IndexWriter.rebuild` захватывает лок непосредственно
  перед scan+write и освобождает в `ensure` (`index_writer.rb:40-48`). Нет
  вложенности с per-task lease/step-локами; нет реентрантности (каждая операция
  захватывает/освобождает ровно один раз). Тест `create → create → delete`
  подтверждает отсутствие самоблокировки одиночной сессии.
- **Retry-on-`:lock_held` корректен.** `Owl::Locks`/`FileLock.acquire`
  НЕблокирующий — возвращает `:lock_held` сразу (`file_lock.rb:118-125`,
  `error_class: :recoverable`). `IndexWriter.acquire` (`index_writer.rb:53-63`)
  строит блокирующее ожидание из примитива: retry с backoff (`RETRY_SLEEP_SECONDS`
  20ms) до ограниченного дедлайна (`ACQUIRE_TIMEOUT_SECONDS` 10s); `clock`/`sleeper`
  инъектируемы. Не-`lock_held` ошибки возвращаются немедленно (без бессмысленного
  retry). TTL примитива (120s, `filesystem.rb:21`) авто-реклеймит упавшего держателя
  (`file_lock.rb:61-69`).
- **Error-path с rollback.** При исчерпании дедлайна возвращается восстановимый
  `Result.err(:lock_held)`. Archive mover теперь обрабатывает ИМЕННО `err`-Result
  (а не только исключения) через общий `archive_index_failed` →
  `rollback_rename` + `restore_task_yaml` (`mover.rb:79-95`). Остальные писатели
  (create/delete/abandon/priority) пробрасывают `err` наверх; их on-disk состояние
  — источник истины, индекс производный и самовосстанавливается при следующем
  успешном rescan, поэтому отдельный rollback им не нужен.
- **Плумбинг `root`.** `root` корректно доведён до точки записи во всех писателях
  (`@root` в filesystem backend; `root:` параметр в deleter/abandon_writer; через
  `Mover.call(root:)` ← `Orchestrator#perform_single` ← `Orchestrator.call(root:)`).
  Лок-файл садится под роль `local_state` (`locks/backends/filesystem.rb:46-51`),
  подтверждено тестом: `.owl/local/index.lock`.

# Findings

Дефектов, требующих изменений, не найдено.

Наблюдения (не блокеры):
1. **Дедлайн retry (10s) << TTL (120s).** Если держатель индекс-лока упал в
   середине записи, конкурирующий писатель в окне до 120s исчерпает 10s-дедлайн и
   получит восстановимый `:lock_held` (корректный сигнал, не вечный wedge —
   следующая операция после истечения TTL реклеймит). Учитывая, что запись индекса
   суб-секундная, а краш ровно во время записи редок, это приемлемый остаточный
   риск, уже отмеченный исполнителем. Константы зашиты в коде; при необходимости
   выносятся в конфиг.
2. **Покрытие `**/api.rb`.** Подтверждено: ни один `lib/owl/**/api.rb` не
   затронут диффом (изменены filesystem/abandon_writer/mover/orchestrator/deleter/
   version + новый internal/index_writer). Полный прогон оставляет все `api.rb` на
   100% — инвариант не нарушен (выполнен вакуумно).

# Resolution

Все acceptance criteria из brief выполнены и проверены независимо. Verdict:
**accepted**. Дополнительных правок кода не требуется.

Независимо прогнанные проверки:
- `bundle exec rspec` → **1793 examples, 0 failures, 1 pending** (преэкзистинг
  SQLite-concurrency placeholder). После прогона `git checkout README.md` (0 paths —
  wart не сработал в этом прогоне).
- `spec/owl/tasks/internal/index_writer_spec.rb` изолированно → **6 examples, 0
  failures**: writes+releases; release-on-exception (leaf); returns lock err без
  rebuild при сбое acquire; timeout → `:lock_held`; retry-success (sleeper-driven
  release); single-session create→create→delete без самоблокировки. Покрывает
  serialization/timeout, retry-success, release-on-exception, no-self-deadlock.
- `bundle exec rubocop` по 8 изменённым файлам → **no offenses** (net-zero).
- `Owl::VERSION` 0.8.0 → 0.8.1 (patch — back-compat hardening), CHANGELOG `[0.8.1]`
  присутствует, `Gemfile.lock` pin синхронизирован.

# Remediation

Не требуется — изменений в коде не запрашивается.

# Residual risks

- Окно «краш во время записи»: до истечения TTL (120s) конкурент получает
  восстановимый `:lock_held` спустя 10s; самовосстанавливается реклеймом по TTL.
  Низкий риск (запись индекса быстрая).
- Лок покрывает только FS-индекс; транзакционный бэкенд (SQLite, P3) — отдельная
  работа.
- `tasks/index.yaml` в рабочем дереве и untracked `tasks/TASK-0021..0024/` —
  backlog-скаффолдинг отдельных задач, НЕ часть этого код-изменения; commit_push
  регенерирует индекс и не должен подмешивать TASK-0022..0024 в коммит TASK-0021.
