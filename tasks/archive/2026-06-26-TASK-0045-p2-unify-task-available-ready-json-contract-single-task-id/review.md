---
status: resolved
summary: >-
  Унифицированный JSON-контракт available/ready/list через TaskSummary реализован
  корректно и полно; все AC выполнены, тесты зелёные (2049/0/1 pending), rubocop
  чист, coverage-gate api.rb = 100%, on-disk формат не тронут, major bump + CHANGELOG.
verdict: accepted
ready: true
---

# Summary

Self-review рефактора TASK-0045: сведение JSON-элемента команд `owl task
available` / `ready` / `list` к единому контракту (ключ идентичности
`task_id` + общее ядро `task_id, title, kind, priority, created_at, status,
workflow` + специфичные поля поверх).

Ревью проведено против `brief.md` (acceptance criteria), `design.md`
(решение и API-контракт) и `plan.md` (чеклист). Проверены: рабочий diff
(`lib/`, `CHANGELOG.md`, `version.rb`, спеки), новый файл
`task_summary.rb`, отсутствие остаточных чтений ключа `id`/`:task_id` у
потребителей, неизменность on-disk формата, тесты, rubocop, smoke-команды.

Вердикт: **accepted**. Реализация соответствует одобренному дизайну/плану,
все AC закрыты, регрессий не обнаружено. Один незначительный nit (дублирование
`priority_of`) — не блокирующий, зафиксирован в Remediation.

# Findings

Использованы уровни: blocker / major / minor / nit.

1. **[nit] Дублирование `priority_of`.** Идентичный по логике метод
   `priority_of(entry)` присутствует и в `lib/owl/tasks/internal/task_summary.rb`
   (стр. 42-45), и в `lib/owl/tasks/internal/availability_scanner.rb`
   (стр. 111-114). В `availability_scanner` он используется только для строки
   `reason` ("priority=#{priority}; oldest ready task"), а в core-поле priority
   попадает значение, посчитанное уже внутри `TaskSummary.project`. Логика
   побайтно одинакова (`Integer ? raw : raw.to_i`), поэтому значения всегда
   совпадают — расхождения семантики нет. Это чистый дубль, не дефект.

Проверенные потенциальные риски — **расхождений не найдено**:

- **Все три команды отдают унифицированный элемент.** Smoke подтвердил:
  `available` (3 эл.) несёт `task_id, status, workflow` и не несёт `id`,
  плюс `ready_step_ids, reason`; `ready` (4 эл.) несёт `task_id, labels`,
  без `id`; `list` (5 эл.) несёт `task_id`, без `id`. Порядок ключей
  каноничен (см. `task_summary.rb`).
- **`--dep-aware`-ветка.** `ReadyAvailabilityScanner` пересекает обе стороны
  по `candidate['task_id']` / `entry['task_id']` (вход уже спроецирован
  `AvailabilityScanner`). Контракт идентичен обычной ветке. Покрыто спеком.
- **Сортировка/ранжирование сохранены.** Проекция — финальный `map` после
  `sort_entries`/`sort_candidates`. `sort_candidates` корректно переведён на
  string-keys (`-c['priority'], c['created_at'].to_s, c['task_id']`);
  `ready_scanner` сортирует на сырых entry (ключ `id`) ДО проекции.
- **Все in-repo потребители обновлены.** Перевод symbol→string и `id`→`task_id`
  в: `commit_push/api` (`task['task_id']`), `orchestration/task_resolver`
  (`top['task_id']`/`top['reason']`), `recall/corpus_builder`
  (`entry['task_id']`), `status/views` (`child_summary['task_id']`),
  `steps/invocation_builder` (`entry['task_id']` для child_ids),
  `claim_service` (`candidate['task_id']`). Grep по остаточным `:task_id`/`['id']`
  показал, что прочие совпадения относятся к другим источникам (claim-lease
  файлы, `Workflows::Api.ready_steps` step-id `s[:id]`, `Archive::Api.list`
  symbol-keyed) — они вне охвата и корректны.
- **On-disk формат не тронут.** `tasks/index.yaml` по-прежнему `- id: ...`;
  `schemas/task.json` не в diff (git status пуст). Проекция строго на выводе.
- **Major bump + CHANGELOG.** `Owl::VERSION` 0.23.1 → 1.0.0; запись в
  `CHANGELOG.md` помечена `Changed (BREAKING)`, точно описывает `id`→`task_id`,
  добавление `status`/`workflow` в `available`, неизменность storage и список
  обновлённых потребителей.

# Resolution

- Finding #1 (nit, дублирование `priority_of`): осознанно **принят как есть**.
  Логика идентична, значения не расходятся; вынос в общий хелпер — косметика
  без функционального эффекта. Не блокирует приёмку.
- Все остальные проверки прошли без замечаний — резолюция не требуется.

Все acceptance criteria из брифа закрыты:
- [x] `available`/`ready`/`list` отдают `task_id`; ключа `id` нет (smoke + спеки).
- [x] Общее ядро core-полей во всех трёх командах с одинаковыми именами/семантикой.
- [x] Специфичные поля сохранены (`ready_step_ids`/`reason`; `parent_id`/`labels`/`blocked_by`/`archived_at`).
- [x] `--dep-aware` отдаёт тот же контракт.
- [x] Внутренние потребители обновлены; спеки зелёные.
- [x] Published JSON-schema на эти выводы отсутствует; `schemas/task.json`
  (on-disk) не тронут.
- [x] Major bump 1.0.0 + запись в CHANGELOG в том же изменении.
- [x] 100% line coverage для затронутых `lib/owl/**/api.rb` (full-run gate пуст).

Проверки выполнены ревьюером:
- `bundle exec rspec spec/owl/tasks spec/owl/cli` → 717 examples, 0 failures.
- `bundle exec rspec` (полный прогон) → 2049 examples, 0 failures, 1 pending
  (предсуществующий storage-backend pending); coverage-gate "Public API files
  below 100%" пуст.
- `bundle exec rubocop lib/owl/tasks` → 48 files, no offenses.
- Smoke `available`/`ready`/`list` → контракт подтверждён.

# Remediation

- (Опционально, не блокирует) Устранить дубль `priority_of`: `availability_scanner`
  может использовать `TaskSummary.priority_of(entry)` для строки `reason`
  вместо локальной копии. Выигрыш косметический; уместно как мелкий cleanup
  в будущем, отдельная задача не обязательна.

# Residual risks

- **Ломающее изменение для consumer-проектов.** `ready`/`list` сменили ключ
  `id`→`task_id`. re/Rrrog и tetris подхватят новый контракт только после
  публикации гема 1.0.0 и `owl upgrade` в каждом проекте (стандартная
  процедура propagation). В этом репозитории все потребители уже обновлены.
- **Известный health-wart SimpleCov.** При частичном прогоне gate показывает
  api.rb-файлы ниже 100% (артефакт частичного покрытия); на полном прогоне
  gate пуст — реального регресса покрытия нет.
- **Предсуществующий offence** `Layout/LineLength` в `task_commands_spec.rb`
  присутствует в HEAD и вне затронутых строк — не относится к этому изменению.
</content>
</invoke>
