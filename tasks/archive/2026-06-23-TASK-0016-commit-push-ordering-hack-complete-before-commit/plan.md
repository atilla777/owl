# Plan — `owl commit-push` (транзакционный commit_push)

## Goal

Реализовать по `tasks/TASK-0016/design.md` модуль `Owl::CommitPush`
(`Api.commit_push` + internal `git_runner`/`transaction`), CLI-команду
`owl commit-push TASK-ID --message M`, и переключить скилл/контекст/оверлей
`commit_push` на один вызов вместо 7-шаговой прозы. Git-операции — через
инъектируемый Open3-раннер; семантика: откат до коммита (step→running), при
провале push коммит сохраняется и команда идемпотентно дотягивает push. Плюс
minor-бамп версии и CHANGELOG.

## Scope

Точечно терминальный шаг `commit_push`: новая команда + перевод скилла/оверлея
на неё. Без обобщения на другие execution-шаги.

## Constraints

- Чистый Ruby + stdlib (`Open3`); без новых внешних gem-ов.
- Git-раннер инъектируемый — спеки НЕ трогают реальный git/сеть.
- Push-lock через `Owl::Locks::Api` с `name: 'git'` (как `owl git lock`);
  release в `ensure`.
- `lib/owl/commit_push/api.rb` — 100% покрытие строк (правило публичного API).
- Идемпотентность: повтор после провала push не создаёт второй коммит.
- Любое изменение поведения → бамп `Owl::VERSION` + CHANGELOG тем же коммитом.

## Files to inspect

- `lib/owl/locks/api.rb` — `acquire/release` (name/token/ttl/steal).
- `lib/owl/cli/internal/commands/git_lock.rb` — образец lock-команды, `name:'git'`.
- `lib/owl/upgrade/internal/shell_runner.rb` — образец Open3-раннера (`Outcome`).
- `lib/owl/steps/api.rb` — `complete`/`reopen`/`reset`/`start` + internal status-writer (флип/откат статуса шага).
- `lib/owl/cli/api.rb` — таблица `dispatch_*` + образец `dispatch_git_lock`.
- `lib/owl/cli/internal/commands/recall.rb` / `archive_list.rb` — образец парсинга команды (TASK-ID + опции, JSON-эмиттер).
- `lib/owl/result.rb` — обёртка ok/err.
- `workflows/{feature,refactor,composite_feature}/commit_push.context.md`, `.owl/overlays/commit_push.md`, `skills/owl-step-execution/SKILL.md` — текущая проза commit_push.
- `lib/owl/version.rb`.

## Checklist

- [ ] `lib/owl/commit_push/internal/git_runner.rb` — `Owl::CommitPush::Internal::GitRunner`: Open3-обёртка (`chdir: root`) c `Outcome(ok,stdout,stderr)`; методы `add_all`, `commit(message)`, `pull_rebase`, `push`, `status_porcelain`, `unpushed?`, `reset_index`/`reset_soft`. Инъектируемый.
- [ ] `lib/owl/commit_push/internal/transaction.rb` — `Transaction.call(root:, task_id:, step_id:, message:, git:, locks:, steps:)`: порядок resolve → idem-retry-branch → add → nothing_to_commit guard → flip done + re-add → lock → commit(rollback на сбое) → pull_rebase → push → release(ensure); возвращает Result.
- [ ] `lib/owl/commit_push/api.rb` — `Owl::CommitPush::Api.commit_push(root:, task_id:, message:, step_id: 'commit_push', git:, locks:, steps:)` делегирует в Transaction; дефолтные зависимости — реальные. 100% покрытие.
- [ ] `lib/owl/cli/internal/commands/commit_push.rb` — парсинг `owl commit-push TASK-ID --message M [--root P] [--json]`; вызов Api; JSON `{ok, task_id, commit_sha, pushed}` / `{ok:false, error}`. `--message` обязателен (иначе `invalid_arguments`).
- [ ] `lib/owl/cli/api.rb` — `require_relative 'internal/commands/commit_push'`, `'commit-push' => :dispatch_commit_push` в таблице, метод `dispatch_commit_push`.
- [ ] `lib/owl/cli/internal/help_text.rb` — usage-строка `commit-push  Atomically stage, complete, commit, and push the commit_push step.`
- [ ] `workflows/{feature,refactor,composite_feature}/commit_push.context.md` — заменить 7-шаговую последовательность на «вызвать `owl commit-push TASK-ID --message "Owl: ..."`; предусловия/stop-conditions выполнить ДО вызова».
- [ ] `.owl/overlays/commit_push.md` — обновить раздел Sequence на один вызов; сохранить Authorization/Preconditions/branch policy.
- [ ] `skills/owl-step-execution/SKILL.md` — если содержит commit_push-специфику, перевести на `owl commit-push`.
- [ ] `lib/owl/version.rb` — minor-бамп `Owl::VERSION`.
- [ ] `CHANGELOG.md` — запись о команде `owl commit-push` (транзакционный commit_push).
- [ ] `spec/owl/commit_push/api_spec.rb` — ветки: успех (один коммит с done + push), nothing_to_commit, откат до коммита (commit fail → running, нет коммита), push_retryable (commit ок, push fail → коммит сохранён), идемпотентный ретрай (повтор дотягивает push, без второго коммита) — 100% api.rb. Git/locks/steps — заглушки.
- [ ] `spec/owl/commit_push/locking_spec.rb` — acquire(name:'git')/release, `lock_held` ретрайбельно, release в ensure при исключении.
- [ ] `spec/owl/cli/commit_push_command_spec.rb` — JSON-форма, обязательность `--message`, проброс ошибок.

## Tests and verification

- `bundle exec rspec spec/owl/commit_push spec/owl/cli/commit_push_command_spec.rb` — зелёные.
- 100% покрытие `lib/owl/commit_push/api.rb`.
- `bundle exec rubocop` по новым/изменённым файлам — чисто.
- Полный `bundle exec rspec` — без регрессий (судить по числу падений, не по exit-коду — известный wart).
- После правки `skills/owl-*`/`workflows/*`/`.owl/overlays/*` — `bin/owl upgrade` (синк `.claude/`/`.owl/`).
- Смоук с временным git-репо (см. ниже) — реальный раннер.

## Smoke test

```
# во временном git-репо с задачей на шаге commit_push (running):
bin/owl commit-push TASK-XXXX --message "Owl: smoke" --json
# => {ok:true, task_id:"TASK-XXXX", commit_sha:"…", pushed:true}
# git log -1 показывает коммит, где task.yaml уже commit_push: done;
# git status чистый; отдельного sync-коммита нет.

# ретрай после провала push (remote недоступен): повтор той же команды
# не создаёт второй коммит, а пытается до-push.
```

## Out of scope

- Транзакционность других execution-шагов (`archive` и пр.).
- Строгий git-reset уже созданного коммита при провале push.
- Изменение политики ветки/remote (push в `main` остаётся).
- Взаимодействие с composite children_complete gate (см. TASK-0019).
- Изменение формата `task.yaml` или контрактов других команд.
