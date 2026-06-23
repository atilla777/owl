# Plan — Composite gate bug fix (aggregate учитывает архивных детей)

## Goal

По `tasks/TASK-0019/design.md`: (1) выставить `parent_id` из архива через
`Owl::Archive::Api.list`; (2) `ChildrenLister` мёржит детей из индекса и архива
(по parent_id, дедуп по task_id, архивный → `status: 'archived'`); (3) гейт
`children_complete` открывается для родителя с полностью архивными детьми, без
ложного открытия для бездетного; (4) одноразовая реконсиляция TASK-0015; (5)
patch-бамп версии + CHANGELOG.

## Scope

Readiness/aggregate-движок composite + archive read-слой (parent_id). Без смены
lifecycle ребёнка и формата task.yaml.

## Constraints

- Cross-domain доступ только через `Owl::Archive::Api` (публичная граница), не Internal.
- `parent_id` — additive поле; форма JSON `list`/`aggregate-status`/`ready-steps` не ломается.
- Архивный ребёнок не должен требовать чтения активного task.yaml (его нет) — state из `status: 'archived'`.
- Бездетный (не декомпозированный) родитель → aggregate `open` (без ложного открытия).
- 100% покрытие затронутых `**/api.rb` (`archive/api.rb`).
- Тронут `lib/**` → patch-бамп `Owl::VERSION` + CHANGELOG тем же коммитом.
- Не ломать не-composite поведение и существующие archive/children/aggregate спеки.

## Files to inspect

- `lib/owl/archive/internal/archive_reader.rb` — `entry_summary`/`read_task_yaml` (читает task.yaml; добавить parent_id, читать payload один раз).
- `lib/owl/archive/api.rb` — `list` (проброс parent_id).
- `lib/owl/tasks/internal/children_lister.rb` — мёрж индекс+архив, дедуп.
- `lib/owl/tasks/internal/aggregate_status.rb` — `child_state`/`aggregate_state` (проверить, что архивный ребёнок даёт 'archived'→'done').
- `lib/owl/tasks/internal/index_reader.rb` — форма index-записи (для совместимого маппинга архивной записи).
- Спеки-образцы: `spec/owl/**` для archive list / aggregate-status / children.

## Checklist

- [ ] `lib/owl/archive/internal/archive_reader.rb` — `entry_summary`: прочитать `read_task_yaml(dir)` один раз, добавить `parent_id: payload['parent_id']` (и `title`). Не менять прочие поля.
- [ ] `lib/owl/archive/api.rb` — убедиться, что `list` пробрасывает `parent_id` (если просто возвращает ArchiveReader.list — автоматически). При необходимости — `show` тоже.
- [ ] `lib/owl/tasks/internal/children_lister.rb` — после сбора индекс-детей добавить архивных: `Owl::Archive::Api.list(root:)` → `select { |a| a['parent_id'] или a[:parent_id] == parent_id }` → смаппить в child-summary с `status: 'archived'` (форма как `base_summary`); дедуп по `id` (предпочесть архивную запись); `require_relative '../../archive/api'`.
- [ ] `lib/owl/tasks/internal/aggregate_status.rb` — проверить/гарантировать, что для архивной записи `child_state` возвращает `'archived'` без чтения активного task.yaml (строка 53 ранний возврат); при необходимости подправить `enrich`/`child_state` под архивную запись.
- [ ] `lib/owl/version.rb` — patch-бамп.
- [ ] `CHANGELOG.md` — запись (Fixed: composite children_complete gate no longer wedges when a child self-archives; Archive list exposes parent_id).
- [ ] `spec/owl/tasks/aggregate_status_archived_children_spec.rb` — (a) wedge: композит с одним ребёнком, ребёнок заархивирован (`owl archive CHILD`) → `aggregate-status` = `done`, `by_child` содержит archived-ребёнка, `ready-steps` показывает `archive` ready; (b) смешанные дети (active+archived) → не `done`; (c) бездетный родитель → `open`.
- [ ] spec на `Owl::Archive::Api.list` → элементы содержат `parent_id`.
- [ ] spec на `ChildrenLister` → мёрж индекс+архив, дедуп по task_id.

## Tests and verification

- `bundle exec rspec spec/owl/tasks spec/owl/archive` — зелёные.
- Полный `bundle exec rspec` — 0 failures (судить по числу падений, не exit-коду — wart); 100% покрытие `lib/owl/archive/api.rb`.
- `bundle exec rubocop` по новым/изменённым файлам — чисто.
- Проверка отсутствия циклического require (`Tasks → Archive::Api`) — полный прогон загрузится без новых circular-варнингов сверх известного storage-варта.

## Smoke test

```
# после фикса — на реальном репо:
bin/owl task aggregate-status TASK-0015 --json   # => aggregate: done, by_child:[TASK-0018 archived]
bin/owl task ready-steps TASK-0015 --json        # => archive в ready (гейт открыт)
bin/owl archive list --json                      # элементы содержат parent_id
```

## Реконсиляция TASK-0015 (одноразовая, в шаге implement/после фикса)

- [ ] После фикса: `owl task aggregate-status TASK-0015` = `done`.
- [ ] `owl step start TASK-0015 archive` → `owl step complete TASK-0015 archive` (гейт открыт; родитель физически уже архивен — это закрытие bookkeeping).
- [ ] `owl step start TASK-0015 commit_push` → завершить (изменения войдут в общий коммit этой поставки; отдельный owl commit-push по TASK-0015 не обязателен — bookkeeping-флипы попадут в коммит TASK-0019).
- [ ] Зафиксировать команды и итог `owl status TASK-0015` в `verification.md`.

## Out of scope

- Запрет self-archive ребёнку / смена его lifecycle.
- Кэш/индекс архива (производительность) — будущая оптимизация.
- Изменение формата task.yaml, атомарного subtree-archive, не-composite поведения.
