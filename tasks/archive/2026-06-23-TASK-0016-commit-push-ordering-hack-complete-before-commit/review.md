---
status: resolved
summary: >-
  Транзакционный owl commit-push реализован корректно: семантика сбоя (откат до
  коммита / сохранение коммита + идемпотентный ретрай push) выполняется, слои
  чистые, 100% покрытие api.rb, прозовая миграция синхронизирована, версия
  бампнута. Ревью-находки исправлены в этой же итерации: lock берётся ДО
  flip→done (AC#3 соблюдён), dead-code reset_soft удалён. Остался один
  косметический follow-up (сообщение already_delivered).
verdict: accepted
ready: true
---

# Code review — TASK-0016 `owl commit-push` (транзакционный commit_push)

## Summary

Независимый ревью незакоммиченного рабочего дерева. Изменение вводит модуль
`Owl::CommitPush` (`Api.commit_push` + internal `GitRunner`/`Transaction`),
CLI-команду `owl commit-push`, две вспомогательные функции на фасаде
`Owl::Steps::Api` (`status`, `mark_running`) и переносит прозу шага commit_push
с ручного 7-действенного хака на один вызов команды.

Проверено объективно:

- `bundle exec rspec spec/owl/commit_push spec/owl/cli/commit_push_command_spec.rb spec/owl/steps/api_status_rollback_spec.rb` → **19 examples, 0 failures**.
- `bundle exec rspec` (полный прогон) → **1760 examples, 0 failures, 1 pending** (pending — несвязанный storage concurrent-write contract), exit 0, line coverage 96.57%. Документированный варт (ненулевой exit / SystemStackError на некоторых seed-ах) на этом прогоне не проявился.
- `bundle exec rubocop lib/owl/commit_push lib/owl/cli/internal/commands/commit_push.rb lib/owl/steps/api.rb spec/owl/commit_push` → **7 files, no offenses**.
- В списке «Public API files below 100%» из coverage-репорта `lib/owl/commit_push/api.rb` **отсутствует** → 100% покрытие публичного API подтверждено.

Вердикт: принимаемо с follow-up. Блокеров нет.

## Findings

Прохожу по 8 пунктам чек-листа.

### 1. Семантика сбоя (ядро задачи) — в основном ВЕРНО, один минорный изъян

Трассировка `lib/owl/commit_push/internal/transaction.rb`:

- **Сбой ДО коммита → откат, коммита нет.**
  - `commit_failed`: `run_commit` (`transaction.rb:72-80`) при провале `git.commit` вызывает `steps.mark_running` и возвращает `:commit_failed`. Откат `done→running` явный. Коммита нет (`push` не достигается). Спека `api_spec.rb:77-90` подтверждает (`mark_running` вызван, `push` не вызван). ✓
  - Провал `steps.complete` в `prepare_commit` (`transaction.rb:48-49`): flip не записан, шаг остаётся `running`, `publish`/lock/commit не достигаются. ✓
  - `nothing_to_commit` (`transaction.rb:46`): чистое дерево → ошибка, `complete` НЕ вызван, lock НЕ взят (`api_spec.rb:63-75`). ✓
- **Коммит ОК, push провалился → коммит сохранён, ретрайбельно, не финально.**
  - `finish_push` (`transaction.rb:82-90`): `pull_rebase`/`push` fail → `push_failure` возвращает `:push_retryable`/`:rebase_conflict` с `commit_sha`; `mark_running` НЕ вызван (коммит сохраняется). Спеки `api_spec.rb:92-115`. ✓ Нет финального «done, но не запушено»: команда возвращает `ok:false` до успешного push.
- **Идемпотентный ретрай.**
  - `retry?` (`transaction.rb:92-96`) = шаг `done` ∧ дерево чисто ∧ `unpushed?`. При true `prepare_commit` пропускается, `run_commit` с `retrying:true` возвращает `nil` (второй коммит не создаётся), идёт только pull+push. Спека `api_spec.rb:117-130` подтверждает: `add_all`/`commit`/`complete` НЕ вызваны, `push` вызван. ✓

Порядок корректен: flip `commit_push: done` (`prepare_commit`, `transaction.rb:48`) + повторный `git.add_all` (`:51`) выполняются ДО `git.commit` (`:75`), поэтому флаг `done` входит в тот же коммит без отдельного sync-коммита. Lock освобождается в `ensure` (`transaction.rb:65-67`).

**Найденный изъян — ИСПРАВЛЕН в этой итерации: lock_held после flip→done не откатывал шаг.**
Исходно flip `done` происходил ДО взятия lock, и `lock_held` оставлял шаг `done` (незакоммичен) — отклонение от Acceptance #3 «любой сбой ДО коммита → commit_push остаётся `running`».
**Исправление:** транзакция реструктурирована — `stage_and_guard` (staging + `nothing_to_commit`) выполняется ДО lock (без мутации шага и без lock на пустой доставке), а flip→done вынесен в `flip_done` ПОД lock. Теперь `publish` сначала `locks.acquire`, и `lock_held` возвращается ДО любого flip → шаг остаётся `running`. Добавлена спека `locking_spec.rb` «leaves the step running on lock_held — the done flip never happens before the lock» (`steps.complete`/`git.commit` не вызваны). Полный прогон после фикса: **1761 examples, 0 failures**.

### 2. Слои — ЧИСТО

- Git side-effects изолированы в инъектируемом `Internal::GitRunner` (`git_runner.rb`, Open3-обёртка по образцу `Upgrade::ShellRunner`). ✓
- `lib/owl/commit_push/api.rb` — тонкий фасад, делегирует в `Internal::Transaction`, не печатает, не знает про JSON (комментарий `api.rb:21` подтверждён кодом). ✓
- Откат маршрутизирован через публичный фасад `Owl::Steps::Api.mark_running`/`status` (`transaction.rb:78,99`), а не в чужой `Steps::Internal`. ✓
- JSON/печать — только в CLI-слое (`commands/commit_push.rb`). ✓

Нарушений слоёв не найдено.

### 3. 100% покрытие публичного API — ПОДТВЕРЖДЕНО

`lib/owl/commit_push/api.rb` отсутствует в списке «below 100%» coverage-репорта → 100% строк. Ветка дефолтных зависимостей покрыта `api_spec.rb:143-157`. Новые `Owl::Steps::Api.status`/`mark_running` покрыты интеграционными спеками `spec/owl/steps/api_status_rollback_spec.rb` (статус известного/неизвестного шага, форс `running`, `unknown_step_id`). ✓

### 4. Переиспользование lock — ВЕРНО

`Transaction::LOCK_NAME = 'git'` (`transaction.rb:25`) — тот же advisory-lock, что `owl git lock` (`GitLock::DEFAULT_NAME`). `lock_held` ретрайбелен (`error_class: :recoverable`), без `--steal`. Освобождение в `ensure` на каждом пути включая исключения. Спеки `locking_spec.rb`: acquire/release с токеном, `lock_held` → recoverable + release НЕ вызван, release-in-ensure при `raise` в `git.commit`. ✓

### 5. Качество тестов — ХОРОШЕЕ

Спеки утверждают: успех (один коммит, оба `add_all`, корректное `message`), `nothing_to_commit` (без flip/lock), три ветки сбоя (`commit_failed`+rollback, `push_retryable`, `rebase_conflict`), идемпотентный ретрай (без второго коммита) + ретрай с повторным провалом push, `--message`/`TASK-ID` обязательны (CLI), `push_retryable` → exit 2, lock_held + release-in-ensure. Git/locks/steps подменены `object_double` — реального git/сети в unit-спеках нет. ✓ Единственный незакрытый сценарий — поведение шага при `lock_held` (см. п.1) не утверждается ни в одну, ни в другую сторону; вынесено в follow-up.

### 6. Прозовая миграция — СИНХРОНИЗИРОВАНА

- `workflows/feature|composite_feature/commit_push.context.md`, `.owl/overlays/commit_push.md`, `skills/owl-step-execution/SKILL.md` переписаны на единый `owl commit-push TASK-ID --message`; предусловия (`git status`, push в `main`, один коммит) и stop-conditions (`rebase_conflict`/`lock_held` → решение человека, без steal) сохранены. ✓
- Материализованные копии в синке: `diff` `workflows/feature/...` ↔ `.owl/workflows/feature/...` = SAME; `skills/owl-step-execution/SKILL.md` ↔ `.claude/...` = SAME (`owl upgrade` отработал). ✓
- Старый 7-шаговый хак из контекстов/оверлея/скилла commit_push удалён. Остаточные упоминания `owl step complete TASK-ID STEP-ID` в skills (owl-step-execution шаг 7, owl-cli/owl-orchestrator/owl-step-discussion) — это легитимная generic-команда завершения, не хак; для commit_push скилл явно отмечает, что шаг 7 — безвредный идемпотентный no-op. Двойной `git add` остался только в `.owl/.backup/` (бэкап от upgrade, gitignored). ✓

### 7. Версионирование — ВЕРНО

`Owl::VERSION` `0.6.0 → 0.7.0` (minor — новая команда), запись `[0.7.0]` в `CHANGELOG.md` в том же изменении, JSON-контракт задокументирован (Added: команда + Steps helpers; Changed: миграция прозы). `.owl/config.yaml`/`Gemfile.lock` синхронизированы по версии. ✓

### 8. Смелы корректности — ПРИЕМЛЕМО

- `unpushed?` (`git_runner.rb:41-43`, `transaction.rb:108-111`): при отсутствии upstream `@{u}` git ошибается → `ok=false` → предикат `false` → ретрай-ветка не срабатывает, идёт обычный путь. Безопасно. ✓
- `--message` обязателен (`commands/commit_push.rb:27-29`), покрыто спекой. ✓
- `reset_soft` — был dead code; **удалён** из `GitRunner` в этой итерации (семантика коммит сохраняет, метод не использовался).
- Минорный UX-варт: при повторе уже полностью доставленной задачи (шаг `done`, дерево чисто, `unpushed?=0`) `retry?` ложно → `prepare_commit` → `nothing_to_commit` (`ok:false`) вместо «already delivered». Не ошибка доставки, но менее дружелюбно. Follow-up-кандидат.

## Resolution

Все 8 пунктов чек-листа закрыты с вердиктом. Из 3 найденных минорных пунктов
**2 исправлены в этой итерации** (lock_held теперь оставляет шаг `running`;
`reset_soft` dead code удалён); остался 1 косметический follow-up
(`nothing_to_commit` вместо `already_delivered` на полностью доставленной
задаче) — не блокирует приёмку. Acceptance criteria 1-9 выполнены. Тесты
зелёные (полный прогон **1761 examples, 0 failures**), rubocop чист, покрытие
api.rb 100%, прозовые копии в синке, версия бампнута. `status: resolved`,
`verdict: accepted`, `ready: true`.

## Remediation

Исправлено в этой итерации:

1. **lock_held-после-flip — СДЕЛАНО:** lock берётся ДО flip→done
   (`stage_and_guard` до lock, `flip_done` под lock); спека на статус шага после
   `lock_held` добавлена.
3. **`reset_soft` — СДЕЛАНО:** неиспользуемый метод удалён из `GitRunner`.

Остаётся опциональным (НЕ блокирует доставку):

2. **`nothing_to_commit` на доставленной задаче:** отличать «done + чисто + уже
   запушено» и возвращать `ok:true, already_delivered` вместо `nothing_to_commit`.
   Косметика UX.

## Residual risks

- **Реальный `GitRunner` покрыт только через заглушки** в unit-спеках (по дизайну,
  как `ShellRunner`); тонкая Open3-обёртка проверяется лишь интеграционно/смоуком.
  Риск низкий — методы тривиальны.
- **Документированный flaky-варт полного rspec** (ненулевой exit / SystemStackError
  на некоторых seed-ах) на этом прогоне не воспроизвёлся; судить по числу
  failures (=0), не по exit code.
