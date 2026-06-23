---
status: shipped
summary: >-
  Новый модуль `Owl::CommitPush` (`Api.commit_push` + internal git_runner /
  transaction), инкапсулирующий stage → flip commit_push=done → re-stage →
  push-lock → commit → pull --rebase → push → unlock как одну транзакцию.
  Git-операции — через инъектируемый Open3-раннер (как upgrade ShellRunner),
  чтобы спеки не трогали реальный git. Откат до коммита возвращает шаг в
  running; при провале push коммит сохраняется и команда идемпотентна (ретрай
  pull+push без второго коммита). CLI `owl commit-push TASK-ID --message M`.
  Скилл/оверлей commit_push упрощаются до одного вызова. Объём — только
  commit_push.
---

# Design — `owl commit-push` (транзакционный commit_push)

## Context

Owl уложен помодульно `Backend → Internal → Api`; CLI — тонкая обёртка над
Api. Релевантные существующие точки:

- **Push-lock:** `Owl::Locks::Api.acquire(root:, name:, ttl:, token:, steal:)` /
  `release(root:, name:, token:)`. Команда `owl git lock` использует
  `name: 'git'` (`GitLock::DEFAULT_NAME`). Новый модуль берёт **тот же** lock
  `name: 'git'`, чтобы сериализоваться с любыми ручными `owl git lock`.
- **Shell-out:** `Owl::Upgrade::Internal::ShellRunner` (`Open3.capture3`,
  инъектируемый, `Outcome(ok, stdout, stderr)`) — образец для git-раннера.
  Сейчас в core нет git-обёртки; commit_push выполняется прозой скилла.
- **Завершение шага:** `Owl::Steps::Api.complete/reopen/reset` и internal
  (`idempotent_complete`, status-writer, что использует `start` для `running`).
  Флип `commit_push: done` пишется в `task.yaml` (для архивной задачи — в её
  каталоге под `tasks/archive/...`).
- **Текущая последовательность** (`commit_push.context.md`, оверлей): `git add`
  → `owl step complete` → `git add` → `owl git lock` → `git commit` →
  `git pull --rebase` → `git push` → `owl git unlock`. Хак: complete-before-
  commit + двойной staging; при отклонении порядка нужен sync-коммит.

`brief` зафиксировал: точечный объём (только commit_push), новая команда
`owl commit-push`, семантика сбоя «до коммита — откат; после commit при провале
push — коммит сохраняется, идемпотентный ретрай».

## Decision

Ввести модуль **`Owl::CommitPush`** и тонкую CLI-обёртку.

### `lib/owl/commit_push/api.rb` — `Owl::CommitPush::Api` (100% покрытие)

```
def self.commit_push(root:, task_id:, message:, step_id: 'commit_push',
                     git: Internal::GitRunner, locks: Owl::Locks::Api,
                     steps: Owl::Steps::Api)
  Internal::Transaction.call(root:, task_id:, step_id:, message:,
                             git:, locks:, steps:)
end
```

Зависимости (`git`/`locks`/`steps`) инъектируются для тестируемости; по
умолчанию — реальные. Api не печатает и не знает про JSON.

### `lib/owl/commit_push/internal/git_runner.rb`

Тонкая обёртка над `Open3.capture3` (как ShellRunner), `chdir: root`. Методы
(каждый → `Outcome`): `add_all`, `commit(message)`, `pull_rebase`, `push`,
`status_porcelain`, `unpushed?` (есть ли коммиты впереди upstream:
`git rev-list @{u}..HEAD`), `reset_soft(ref:'HEAD~1')` (для отката, если
понадобится). Инъектируемый — спеки подменяют раннер заглушкой.

### `lib/owl/commit_push/internal/transaction.rb` — ядро

Порядок (одна операция):

1. **Резолв** root/git-repo; прочитать статус `commit_push`.
2. **Идемпотентная ветка ретрая:** если рабочее дерево чистое
   (`status_porcelain` пусто), шаг уже `done`, и `unpushed?` → это ретрай
   после провала push: перейти сразу к шагу 6 (lock → pull --rebase → push),
   НЕ создавая второй коммит.
3. `git add_all`.
4. **Guard «нечего коммитить»:** если после add дерево всё ещё пустое
   (нет изменений) и не ретрай → вернуть `ok:false, nothing_to_commit`, не
   флипать `done`.
5. **Flip → done:** `steps.complete(commit_push)` (или internal status-writer)
   пишет `commit_push: done` в `task.yaml`; затем `git add_all` ещё раз (флип в
   индекс — теперь часть будущего коммита). До этого момента откат тривиален.
6. **Сериализованный коммит+пуш:**
   a. `locks.acquire(name: 'git')` → `token`. На `lock_held` → вернуть
      ретрайбельную ошибку (не `--steal`).
   b. (ретрай-путь начинается здесь) Если ещё не коммитили: `git commit(message)`.
      **Сбой commit → откат:** вернуть `commit_push` в `running` (un-flip),
      `git reset` индекса при необходимости, release lock, `ok:false`.
   c. `git pull_rebase`. Конфликт/сбой → коммит уже есть (сохраняется), release
      lock, `ok:false, push_retryable` (шаг остаётся фактически `done` в
      коммите; рабочее дерево чистое; повтор команды дотянет push).
   d. `git push`. Сбой → как (c): коммит сохранён, `ok:false, push_retryable`.
   e. `locks.release(name:'git', token:)` (в `ensure`).
7. Успех → `ok:true` с `commit_sha`, `pushed:true`.

**Семантика сбоя (из brief):**
- сбой ДО `git commit` → `commit_push` = `running`, коммита нет;
- `git commit` ок, но `pull --rebase`/`push` упал → локальный коммит (с `done`
  внутри) сохранён; команда идемпотентна — повтор идёт по ветке ретрая (шаг 2)
  и дотягивает только pull+push; «done, но не запушено» не финально — пока
  push не прошёл, команда возвращает `ok:false`.

### CLI `lib/owl/cli/internal/commands/commit_push.rb`

`owl commit-push TASK-ID --message M [--root P] [--json]`. Зовёт
`Owl::CommitPush::Api.commit_push`, сериализует Result в JSON
(`{ok, task_id, commit_sha, pushed}` или `{ok:false, error:{code,...}}`).
Регистрация: `require_relative 'internal/commands/commit_push'`,
`'commit-push' => :dispatch_commit_push` в `lib/owl/cli/api.rb`, usage в
`help_text.rb`. `--message` обязателен (composer сообщения остаётся за
скиллом).

### Скилл/оверлей commit_push

`workflows/*/commit_push.context.md` + `.owl/overlays/commit_push.md` +
`skills/owl-step-execution` (раздел commit_push): заменить 7-шаговую прозу на
один вызов `owl commit-push TASK-ID --message "Owl: ..."`; предусловия
(`git status` на посторонние файлы, push в `main`, один коммит) и
stop-conditions сохранить как предобработку перед вызовом. После правки
`skills/owl-*`/`workflows/*` — `owl upgrade` для синка `.claude/`/`.owl/`.

### Версия

`Owl::VERSION` minor-бамп; `CHANGELOG.md` тем же коммитом (Конституция §7.1).

## Alternatives

- **Транзакционный `owl step complete` для commit_push** (complete сам коммитит+
  пушит). Отвергнуто в brief: перегружает семантику `step complete`, труднее
  тестировать изолированно, неожиданно для других шагов.
- **Минимальный откат в прозе скилла** (без новой команды). Отвергнуто: логика
  остаётся не покрытой тестами и дублируется в каждом workflow-оверлее.
- **Строгий git-откат уже созданного коммита при провале push** (`reset --hard`).
  Отвергнуто: рискованно (потеря работы), brief выбрал «коммит сохраняется,
  ретрай push».
- **Обобщить транзакционность на `archive`/все side-effect шаги.** Вне объёма
  (brief: точечно commit_push).
- **Свой новый lock-name** вместо `'git'`. Отвергнуто: разъехался бы с
  `owl git lock`; переиспользуем `name: 'git'`.

## Risks

- **Внесение git shell-out в core.** Митигация: инъектируемый `GitRunner`
  (как ShellRunner); спеки гоняют Transaction с заглушкой git — без реального
  git/сети. Тонкий реальный раннер покрывается интеграционно/смоуком.
- **Корректность идемпотентного ретрая** (распознать «коммит есть, push нет»).
  Митигация: явный предикат (чистое дерево + шаг `done` + `unpushed?`); спеки на
  обе ветки (первый прогон / ретрай после провала push).
- **Откат флипа `done`→`running` при сбое до коммита** не должен повредить
  остальной `task.yaml`. Митигация: точечное изменение статуса шага; спека на
  откат.
- **Lock release при исключении.** Митигация: `ensure`-release; спека на путь с
  падением между acquire и release.
- **Композитные задачи** (gate children_complete, архивный путь) — вне объёма;
  команда не лезет в composite-gate (см. TASK-0019).
- **Backward-compat:** меняется проза скилла/оверлея и JSON-контракт новой
  команды. Митигация: контракт зафиксирован ниже и в спеках; старые ручные шаги
  остаются возможны (lock/complete/commit), но рекомендуемый путь — одна команда.

## API

**Ruby (внутренний публичный):**

```
Owl::CommitPush::Api.commit_push(root:, task_id:, message:,
                                 step_id: 'commit_push')
  => Result.ok(task_id:, commit_sha:, pushed: true)
   | Result.err(code: :nothing_to_commit | :lock_held | :commit_failed
                      | :push_retryable | :rebase_conflict | ...,
                message:, details:)
  # до коммита fail  → commit_push = running, коммита нет
  # commit ок/push fail → коммит сохранён; повтор идемпотентен (ретрай push)
  # push-lock name: 'git' (как owl git lock)
```

**CLI:**

```
owl commit-push TASK-ID --message "Owl: <subject>" [--root PATH] [--json]
```

**JSON (успех):**

```json
{ "ok": true, "task_id": "TASK-0016",
  "commit_sha": "abc123…", "pushed": true }
```

**JSON (ретрайбельный провал push, коммит сохранён):**

```json
{ "ok": false,
  "error": { "code": "push_retryable",
             "message": "commit created; push failed — re-run owl commit-push to retry",
             "details": { "commit_sha": "abc123…" } } }
```

- Команда атомарна с точки зрения вызывающего: либо доставлено (commit с `done`
  внутри + push), либо состояние консистентно для ретрая.
- Push сериализован lock-ом `name: 'git'`; `lock_held` → ретрайбельно, без steal.
- Предусловия `git status` (посторонние файлы) выполняет скилл ДО вызова.

**Тесты (план):** `spec/owl/commit_push/api_spec.rb` (контракт + ветки: успех,
nothing_to_commit, откат до коммита, push_retryable, идемпотентный ретрай —
100% api), `spec/owl/commit_push/locking_spec.rb` (acquire/release, lock_held,
release в ensure), CLI-спек на JSON-форму.
