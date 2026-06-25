---
status: approved
summary: "Intersection design: ReadyScanner excludes on_hold/blocked; add dep-aware opt-in to Tasks::Api.available (available-candidates ∩ deps+status ready-ids); ClaimService.claim_next and TaskResolver.auto_select both use it. available default stays dep-blind. Minor bump + CHANGELOG."
---

# Goal

Сделать авто-выбор/авто-claim задачи deps+status-aware в ОБОИХ местах
(`ClaimService.claim_next` и `TaskResolver.auto_select`), как пересечение
available-кандидатов (есть готовый шаг, не заклеймлено) с deps+status-гейтом
(`blocked_by` завершены, статус не on_hold/blocked/terminal). `owl task available`
по умолчанию остаётся dependency-blind.

# Scope

- `lib/owl/tasks/internal/ready_scanner.rb` — исключить `on_hold`/`blocked` из ready.
- `lib/owl/tasks/internal/availability_scanner.rb` ИЛИ новый внутренний хелпер —
  пересечение available-кандидатов с deps+status ready-id-множеством (dep-aware режим).
- `lib/owl/tasks/api.rb` — `available(root:, dep_aware: false)` (новый keyword; дефолт
  сохраняет dep-blind контракт).
- `lib/owl/tasks/internal/claim_service.rb` — `claim_next` зовёт dep-aware скан.
- `lib/owl/orchestration/internal/task_resolver.rb` — `auto_select` зовёт
  `Tasks::Api.available(dep_aware: true)`.
- `lib/owl/version.rb` + `CHANGELOG.md` — minor bump (0.15.1 → 0.16.0).

# Constraints

- НЕ менять дефолтный вывод `owl task available` / `Tasks::Api.available` (dep-blind);
  докстринг и существующие тесты в силе.
- `TaskResolver` остаётся read-only (никаких claim/mutation).
- explicit TASK-ID и current_pointer резолв — без изменений.
- НЕ терять фильтр «есть готовый шаг» (он у AvailabilityScanner) — поэтому пересечение,
  не замена на ready.
- Слой: `TaskResolver` (orchestration) обращается к `Tasks::Api`, НЕ к tasks/internal.
- 100% покрытие тронутых `**/api.rb` (обе ветки нового keyword); RuboCop net-zero.
- Constitution §7.1: minor bump VERSION + CHANGELOG в том же коммите.

# Files to inspect

- `lib/owl/tasks/internal/ready_scanner.rb` (TERMINAL_STATUSES, ready_entry?, deps_complete?).
- `lib/owl/tasks/internal/availability_scanner.rb` (candidate_hash, ready_step_ids, sort).
- `lib/owl/tasks/internal/claim_service.rb` (claim_next → claim_first_available; читает
  `candidate[:task_id]`).
- `lib/owl/tasks/api.rb` (available, ready — сигнатуры/докстринги).
- `lib/owl/orchestration/internal/task_resolver.rb` (auto_select, none_resolution; читает
  `candidate reason`).
- `spec/owl/tasks/**` (ready_scanner, availability, claim_service specs),
  `spec/owl/orchestration/**` (task_resolver / instructions specs).

# Checklist

- [ ] `ready_scanner.rb`: ввести `NON_READY_STATUSES = (TERMINAL_STATUSES + %w[on_hold
      blocked]).freeze`; в `ready_entry?` проверять собственный статус по нему вместо
      `TERMINAL_STATUSES`. Deps-логика без изменений. (Опц.) экспонировать множество
      ready-id для переиспользования.
- [ ] dep-aware пересечение: получить available-кандидатов (AvailabilityScanner) и
      оставить только те, чей `task_id` ∈ ready-id-множество (ReadyScanner). Реализовать
      как внутренний хелпер (напр. `ReadyAvailabilityScanner.scan` или приватный путь),
      возвращающий тот же формат, что available (`{task_id, priority, reason,
      ready_step_ids, …}`), в том же порядке.
- [ ] `Tasks::Api.available(root:, dep_aware: false)`: при `false` — текущий
      AvailabilityScanner; при `true` — пересечение. Покрыть обе ветки.
- [ ] `claim_service.rb#claim_next`: вместо `AvailabilityScanner.scan` использовать
      dep-aware скан (через тот же внутренний хелпер). `claim_first_available` не
      меняется (формат кандидата тот же).
- [ ] `task_resolver.rb#auto_select`: `Owl::Tasks::Api.available(root:, dep_aware: true)`;
      взять первого кандидата; reason — из кандидата (`candidate[:reason]`); пустой →
      `none_resolution`.
- [ ] `CHANGELOG.md`: deps+status-aware авто-выбор/авто-claim (`owl next`, `claim
      --next`); `owl task ready` теперь скрывает `on_hold`/`blocked`.
- [ ] `lib/owl/version.rb`: 0.15.1 → 0.16.0.

# Tests and verification

- [ ] ReadyScanner: `on_hold`/`blocked` задача не в ready; dep-заблокированная не в
      ready; dep→done появляется; сортировка неизменна.
- [ ] dep-aware available: задача без готового шага НЕ попадает (фильтр available
      сохранён); dep-заблокированная/`on_hold` НЕ попадает; обычная — попадает с reason.
- [ ] `Tasks::Api.available` дефолт (`dep_aware: false`): dep-заблокированная/`on_hold`
      задача ПРИСУТСТВУЕТ (контракт dep-blind сохранён).
- [ ] `claim_next`: не клеймит dep-заблокированную/`on_hold`; клеймит первую готовую.
- [ ] `TaskResolver.auto_select`: без current dep-заблокированную/`on_hold` не выбирает
      (`source: none`, если нет других); обычную — выбирает; explicit/current не затронуты.
- [ ] `bundle exec rspec` зелёный; 100% покрытие тронутых `**/api.rb`.
- [ ] `bundle exec rubocop <тронутые файлы>` net-zero.

# Smoke test

```
owl task create --workflow quick --title A          # TASK-A
owl task create --workflow quick --title B          # TASK-B
owl task dep add TASK-B --on TASK-A                  # B blocked_by A
owl task ready --json                                # A да, B нет
owl task claim --next --json                         # клеймит A (не B)
owl task release TASK-A <token>
owl task set-status TASK-A on_hold
owl task ready --json                                # A исчезает
owl task available --json                            # A всё ещё есть (dep-blind)
owl task set-status TASK-A done
owl task ready --json                                # теперь содержит B
```

# Out of scope

- Изменение дефолтного `owl task available`/`AvailabilityScanner` вывода.
- `owl step reset` не чистит active-step-lock (отдельная находка/follow-up — НЕ чинить
  здесь).
- Per-task.yaml mutation-лок, scoped-staging commit-push, CLI-рендер unchanged-счётчиков.
