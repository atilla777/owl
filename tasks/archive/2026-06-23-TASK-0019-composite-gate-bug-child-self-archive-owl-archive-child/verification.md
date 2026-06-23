---
status: passed
summary: >-
  Фикс composite children_complete-гейта реализован и проверен: ChildrenLister
  мёржит архивных детей через публичную границу Owl::Archive::Api.list (дедуп по
  task_id), archive list выставляет parent_id. Полный rspec — 1777 examples,
  0 failures, 1 pending. archive/api.rb 100% покрыт, rubocop чист, нового
  циклического require нет (счётчик archive/api.rb:3 = 28 идентичен clean main —
  это известный wart). Реальный wedge на TASK-0015 снят: aggregate стал done,
  шаги archive/commit_push доведены до done.
---

# Verification — Composite gate bug fix (aggregate учитывает архивных детей)

## Summary

Реализованы все пункты чеклиста `plan.md`:

- `lib/owl/archive/internal/archive_reader.rb` — `entry_summary` читает архивный
  `task.yaml` один раз (payload) и выставляет `title` + новое additive-поле
  `parent_id`. `Owl::Archive::Api.list` пробрасывает его наружу.
- `lib/owl/tasks/internal/children_lister.rb` — после сбора детей из активного
  индекса добавляет архивных детей: `Owl::Archive::Api.list(root:)` →
  фильтр по `parent_id` (пустой parent_id игнорируется) → маппинг в child-summary
  со `status: 'archived'` (форма как `base_summary` + `progress`); дедуп по `id`,
  предпочитая архивную (терминальную) запись. Require идёт через публичную
  границу `Owl::Archive::Api`, но **лениво** (внутри метода `archived_children`),
  чтобы не вносить load-time цикл `archive/api → tasks/api → backends/filesystem →
  children_lister`.
- `lib/owl/tasks/internal/aggregate_status.rb` — без изменений: `child_state`
  уже возвращает `'archived'` по `status: 'archived'` (строка 53), а
  `aggregate_state` даёт `done` для all-archived и `open` для пустого `by_child`.
- `lib/owl/version.rb` — patch-бамп `0.7.1 → 0.7.2`; `CHANGELOG.md` — запись
  (Fixed: гейт не залипает при self-archive ребёнка; Added: archive list
  выставляет parent_id) тем же изменением.
- Спека `spec/owl/tasks/aggregate_status_archived_children_spec.rb` (5 примеров):
  wedge-fixed, mixed (active+archived), бездетный → open, `Archive::Api.list`
  содержит parent_id, `ChildrenLister` мёрж индекс+архив с дедупом.

## Commands

```
# Загрузка модулей в обоих порядках (нет нового цикла):
ruby -Ilib -e 'require "owl/archive/api"; require "owl/tasks/api"'   # OK
ruby -Ilib -e 'require "owl/tasks/api"; require "owl/archive/api"'   # OK

# Целевые спеки:
bundle exec rspec spec/owl/tasks/aggregate_status_archived_children_spec.rb
  # => 5 examples, 0 failures
bundle exec rspec spec/owl/tasks spec/owl/archive
  # => 195 examples, 0 failures ; archive/api.rb 100% (нет в below-100 списке)

# Полный прогон:
bundle exec rspec
  # => 1777 examples, 0 failures, 1 pending

# Линт:
bundle exec rubocop lib/owl/archive/internal/archive_reader.rb \
  lib/owl/tasks/internal/children_lister.rb lib/owl/version.rb \
  spec/owl/tasks/aggregate_status_archived_children_spec.rb
  # => 4 files inspected, no offenses detected

# Smoke на реальном репо (TASK-0015 — застрявший родитель):
bin/owl task aggregate-status TASK-0015 --json
  # ДО фикса: aggregate:'open', by_child:[]  (wedge)
  # ПОСЛЕ фикса: {"aggregate":"done","by_child":[{"id":"TASK-0018","state":"archived","status":"archived"}]}
bin/owl task ready-steps TASK-0015 --json
  # => ready:[{"id":"archive",...}]  (гейт children_complete открыт)
bin/owl archive list --json
  # => элементы содержат parent_id

# Реконсиляция TASK-0015 (одноразовая, только bookkeeping; git не запускался):
bin/owl step start    TASK-0015 archive
bin/owl step complete TASK-0015 archive
bin/owl step start    TASK-0015 commit_push
bin/owl step complete TASK-0015 commit_push
bin/owl status TASK-0015 --json
  # => все 6 шагов done, progress 100.0
```

## Outcomes

- **Wedge воспроизведён и снят** (спека + реальный TASK-0015): композит, у
  которого единственный ребёнок самоархивирован, теперь даёт `aggregate: done`,
  `by_child` содержит архивного ребёнка со state `archived`, а `archive` —
  ready.
- **Нет ложного открытия:** бездетный композит по-прежнему `aggregate: open`,
  `by_child: []`.
- **Mixed:** active+archived → не `done`; архивный ребёнок присутствует со state
  `archived`, активный — `in_progress`.
- **`Owl::Archive::Api.list`** выставляет `parent_id` (additive; форма JSON не
  сломана).
- **`ChildrenLister`** мёржит индекс+архив с дедупом по task_id.
- **Покрытие:** `lib/owl/archive/api.rb` — 100% (не попадает в below-100 список).
- **Циклический require:** счётчик строк `archive/api.rb:3` на stderr прогона
  `spec/owl/tasks spec/owl/archive` = **28** и на ветке, и на чистом `main` —
  идентично, то есть **нового** цикла не внесено (это задокументированный
  pre-existing storage/tasks-wart; полный suite всё равно зелёный).
- **TASK-0015 реконсилирован:** `aggregate-status` = `done`; шаги `archive` и
  `commit_push` доведены до `done`; `owl status TASK-0015` — 6/6 done,
  progress 100.0, без залипших pending-шагов. Физически задача уже в
  `tasks/archive/2026-06-23-TASK-0015-surface/`; CLI резолвит её по id.

## Not run

- Никаких git-операций (commit/push) в этом шаге — bookkeeping-флипы TASK-0015
  и TASK-0019 войдут в общий коммит поставки на шаге `commit_push` оркестратором.
- Производительность скана архива на каждый aggregate-вызов не профилировалась —
  отмечено в design/brief как будущая оптимизация (кэш/индекс архива).

## Failures or blockers

- Нет. Все целевые и полный прогон зелёные; реконсиляция прошла идемпотентно.

## Residual risks

- **Скан архива O(n) на каждый aggregate-вызов** (`Archive::Api.list` читает
  каждый архивный `task.yaml`): на текущем масштабе (десятки задач) дёшево, на
  больших архивах — кандидат на индексацию.
- **Ленивый require в `archived_children`** опирается на то, что к моменту вызова
  всё загружено (так и есть в рантайме); top-level require пришлось убрать именно
  из-за load-time цикла `archive/api ↔ tasks/api`. Покрыто проверкой обоих
  порядков загрузки и полным прогоном.
- **Старый формат архива без `parent_id`** → `parent_id` nil → запись не
  считается ребёнком (не падает); дедуп по task_id защищает от дублей.
- **Pre-existing SystemStackError-wart** (storage/tasks circular require) остаётся
  как был (счётчик не вырос); полный suite судится по числу падений (0), не по
  exit-коду.
