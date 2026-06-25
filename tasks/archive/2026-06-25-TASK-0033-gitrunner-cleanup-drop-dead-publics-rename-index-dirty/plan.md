---
status: approved
summary: "Удалить status_porcelain/add_all из GitRunner; index_dirty?→index_clean? (git_runner + transaction + 3 спека). grep-проверка 0 вхождений index_dirty?. patch bump 0.17.0→0.17.1."
---

# Goal

Чистый рефакторинг GitRunner: убрать мёртвые publics, переименовать `index_dirty?`
→ `index_clean?`. Поведение `owl commit-push` неизменно.

# Scope

- `lib/owl/commit_push/internal/git_runner.rb` — удалить `status_porcelain`,
  `add_all`; переименовать `index_dirty?` → `index_clean?`; поправить комментарий.
- `lib/owl/commit_push/internal/transaction.rb` — `index_empty?` зовёт
  `git.index_clean?(root:).ok`.
- `spec/owl/commit_push/git_runner_spec.rb`, `api_spec.rb`, `locking_spec.rb` —
  заменить `index_dirty?` → `index_clean?`.
- `lib/owl/version.rb` + `CHANGELOG.md` — patch bump 0.17.0 → 0.17.1.

# Constraints

- Реализация `index_clean?` = прежняя `index_dirty?` (git diff --cached --quiet),
  `Outcome.ok = git success`. Никакого изменения поведения/семантики.
- Не трогать публичный CLI/JSON-контракт.
- rspec зелёный, 0 failures; 100% покрытие `**/api.rb`; RuboCop net-zero.
- Constitution §7.1: patch bump VERSION + CHANGELOG в том же коммите.

# Files to inspect

- `lib/owl/commit_push/internal/git_runner.rb` (методы + комментарий add_scoped).
- `lib/owl/commit_push/internal/transaction.rb:134-136` (index_empty? helper).
- `spec/owl/commit_push/git_runner_spec.rb` (describe '.index_dirty?', 2 вызова).
- `spec/owl/commit_push/api_spec.rb` (fake_git ключ + комментарий + 3 use-site).
- `spec/owl/commit_push/locking_spec.rb` (happy_git ключ).

# Checklist

- [ ] Удалить `def status_porcelain` и `def add_all` из git_runner.rb.
- [ ] Переформулировать комментарий `add_scoped` (без отсылки к `add_all`).
- [ ] Переименовать `def index_dirty?` → `def index_clean?` (тело без изменений).
- [ ] transaction.rb: `git.index_dirty?` → `git.index_clean?` в `index_empty?`.
- [ ] Заменить `index_dirty?` → `index_clean?` во всех 3 спеках (ключи fake_git,
      describe, вызовы); поправить описания тестов на «clean/empty index».
- [ ] grep `index_dirty?` по lib/ + spec/ → 0 вхождений; grep `status_porcelain`,
      `add_all` → 0 вхождений (кроме, возможно, истории CHANGELOG — не трогать).
- [ ] CHANGELOG.md (Changed/Internal): GitRunner cleanup — удалены мёртвые
      status_porcelain/add_all; index_dirty? переименован в index_clean? (поведение
      без изменений).
- [ ] version 0.17.0 → 0.17.1.

# Tests and verification

- [ ] `bundle exec rspec` зелёный, 0 failures, покрытие `**/api.rb` 100%.
- [ ] `bundle exec rubocop lib/owl/commit_push/internal/git_runner.rb
      lib/owl/commit_push/internal/transaction.rb spec/owl/commit_push/*` net-zero.
- [ ] grep подтверждает отсутствие старых имён.

# Smoke test

```
grep -rn "index_dirty?\|status_porcelain\|\.add_all\|:add_all" lib/ spec/   # → пусто
bundle exec rspec spec/owl/commit_push/   # (полный прогон для coverage-gate отдельно)
```

# Out of scope

- Изменение поведения staging/guard/retry (TASK-0032 уже доставлен).
- Переименование transaction-хелпера `index_empty?` (читается ясно, оставляем).
- per-task lock / spec-merge unchanged CLI render / P3 / F2.2.
