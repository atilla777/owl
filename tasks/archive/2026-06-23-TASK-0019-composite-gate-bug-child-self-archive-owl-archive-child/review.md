---
status: resolved
summary: >-
  Независимое ревью фикса composite children_complete-гейта. Wedge подтверждённо
  снят: ChildrenLister мёржит архивных детей через публичную границу
  Owl::Archive::Api.list (дедуп по task_id, архив терминально побеждает), и
  полностью архивный ребёнок даёт aggregate=done → гейт открывается. Ложного
  открытия для бездетного родителя нет (empty by_child → 'open' цел). Ленивый
  require обоснован и проверен (нет нового цикла; счётчик circular-warning 14=14
  ветка vs main). Реконсиляция TASK-0015 корректна (6/6 done, без фейкового git).
  Полный rspec — 1777 examples, 0 failures, 1 pending; rubocop чист. Patch-бамп
  0.7.1→0.7.2 + CHANGELOG — верно. Багов не найдено.
verdict: accepted
ready: true
---

# Code review — Composite gate bug fix (aggregate учитывает архивных детей)

## Summary

Фикс соответствует brief/design/plan и не имеет блокеров. Корень проблемы устранён
на правильном слое: `ChildrenLister` теперь складывает детей из активного
`tasks/index.yaml` И архивных детей, найденных по `parent_id` через **публичную**
границу `Owl::Archive::Api.list`, а `AggregateStatus` остаётся неизменным
(`status: 'archived'` → state `archived` → all-archived → `done`). Изменение
аддитивно (поле `parent_id` в archive list), back-compat, заслуженно — patch.

Я независимо прогнал целевую спеку (5 examples, 0 failures), `spec/owl/tasks` +
`spec/owl/archive` (195, 0), полный `bundle exec rspec` (**1777 examples,
0 failures, 1 pending**), rubocop по затронутым файлам (4 files, no offenses), а
также реальные `aggregate-status`/`status` по TASK-0015. Все зелёные.

## Findings

Прохожу по 9 пунктам чеклиста; вердикт + ссылка на файл:строку для каждого.

1. **Wedge действительно снят — OK.** Трасса `ChildrenLister.call`
   (`lib/owl/tasks/internal/children_lister.rb:17-32`) → `merge_archived`
   (`:37-43`) → `archived_children` (`:45-57`): архивные дети с непустым
   `parent_id` маппятся в summary со `status: 'archived'`
   (`archived_summary`, `:59-68`). `AggregateStatus.child_state`
   (`lib/owl/tasks/internal/aggregate_status.rb:53`) шорткатит на
   `status == 'archived'` → state `archived`; `aggregate_state` (`:69`) для
   all-archived → `done`. Подтверждено спекой
   (`spec/owl/tasks/aggregate_status_archived_children_spec.rb:66-86`) И живым
   репо: `bin/owl task aggregate-status TASK-0015 --json` →
   `{"aggregate":"done","by_child":[{"id":"TASK-0018","state":"archived",
   "status":"archived"}]}`.

2. **Нет ложного открытия для бездетного родителя — OK (критично).** Путь
   `aggregate_state` сохранил `return 'open' if by_child.empty?`
   (`aggregate_status.rb:67`). `merge_archived` при пустом архиве возвращает
   `index_children` без изменений (`children_lister.rb:39`), а при отсутствии
   детей и там, и там `by_child` пуст → `'open'`. Спека прямо это покрывает
   (`aggregate_status_archived_children_spec.rb:108-121`): бездетный composite →
   `aggregate == 'open'`, `by_child == []`. Регрессии нет.

3. **Дедуп — OK.** `merge_archived` (`children_lister.rb:41-42`) выкидывает из
   `index_children` записи, чьи id присутствуют среди архивных, затем
   доклеивает архивные — то есть архив (терминальное состояние) побеждает, как и
   задумано в design. Замечание (не блокер): спека
   (`:142-163`) проверяет лишь отсутствие дубликатов при «один архив + один
   активный»; истинная коллизия «один и тот же id в индексе И в архиве» спекой
   не воспроизводится. Логика верна по чтению; покрытие этого edge помечаю как
   нестрогий follow-up.

4. **Ленивый require — OK, обоснован.** `require_relative '../../archive/api'`
   вынесен внутрь метода `archived_children` (`children_lister.rb:50`). Цикл
   реален и подтверждён: `archive/api.rb:3` →`require_relative '../tasks/api'`,
   а `tasks/api` → `tasks/backends/filesystem` → `children_lister`
   (`grep` подтвердил `lib/owl/archive/api.rb:3` и
   `lib/owl/tasks/backends/filesystem.rb`). К моменту вызова всё загружено;
   симуляция `require 'owl/tasks/internal/children_lister'` затем
   `require 'owl/archive/api'` грузится чисто и `Owl::Archive::Api.list`
   доступен. Документированный pre-existing wart (`archive/api.rb:3` →
   `storage/api.rb:4` «circular require») **не изменён**: счётчик circular-
   warning на `spec/owl/archive` = **14 и на ветке, и на застэшенном main**
   (идентично). Нового цикла не внесено; полный suite грузится чисто.

5. **Слои — OK.** Cross-domain доступ идёт через публичный `Owl::Archive::Api`
   (`children_lister.rb:51`), не через `Archive::Internal`. В `archive_reader.rb`
   `entry_summary` (`lib/owl/archive/internal/archive_reader.rb:97-107`) читает
   `task.yaml` РОВНО один раз (`payload = read_task_yaml(entry[:dir])`, `:98`) и
   берёт из него `title` + `parent_id` — раньше тоже был один read ради title,
   значит лишнего I/O не добавлено. Прямого FS в Tasks по архиву нет.

6. **Аддитивность/back-compat — OK.** `parent_id` — новое необязательное поле в
   элементах `archive list` (`archive_reader.rb:104`); форма JSON
   `aggregate-status`/`ready-steps` не меняется, `by_child` лишь становится
   полнее. Не-composite ветка не затронута (aggregate доступен только для
   `composite_task`, `aggregate_status.rb:27-33`).

7. **Реконсиляция TASK-0015 — OK, легитимна.** Diff
   `tasks/archive/2026-06-23-TASK-0015-surface/task.yaml` флипает только
   `archive` и `commit_push` `pending → done` (status-only). Никаких git-
   операций в шаге не выполнялось (verification это прямо фиксирует;
   `git status` чист по содержимому, кроме ожидаемых флипов). `bin/owl status
   TASK-0015 --json` → все 6 шагов `done`, progress 100.0, blockers пуст. Это
   корректное закрытие bookkeeping физически уже заархивированного родителя, а не
   порча данных: `aggregate-status` независимо подтверждает `done`, так что гейт
   и так был бы открыт.

8. **Версионирование — OK.** `lib/owl/version.rb` `0.7.1 → 0.7.2` (patch),
   `Gemfile.lock` синхронизирован, `CHANGELOG.md` — записи Fixed (гейт) + Added
   (`parent_id` в archive list). Back-compat баг-фикс readiness-движка → patch —
   правильный уровень SemVer.

9. **Качество тестов — OK (с мелкой оговоркой).** Спека строит **реальный**
   wedge: `owl task create` родитель/дети, `step start/complete`, `owl archive
   CHILD` (`:60-64`), затем проверяет `aggregate == 'done'` и наличие `archive`
   в `ready-steps` (гейт открыт). Покрыты: wedge-fixed, mixed (active+archived ≠
   done), бездетный → open, `parent_id` через `Archive::Api.list`, мёрж+дедуп в
   `ChildrenLister`. Сценарии не поверхностные — гоняют через CLI и публичный
   API. Единственный пробел — истинная id-коллизия индекс∩архив (см. п.3).

## Resolution

Все 9 пунктов — pass. Блокеров нет. Артефакт `verification` (авторства
`implement`) точен и согласуется с моими независимыми прогонами (включая счётчик
circular-warning и реконсиляцию TASK-0015). Багов в коде не обнаружено.

Вердикт: **accepted**, `ready: true`. Шаг готов к `merge_docs` без возврата на
`implement`.

## Remediation

Действий-блокеров не требуется. Опциональный (необязательный) follow-up:

- Добавить в спеку прямой кейс на дедуп при истинной коллизии id (одна и та же
  задача присутствует и в `tasks/index.yaml`, и в архиве) — утвердить, что
  архивная запись побеждает и дубликата нет. Текущая логика
  (`children_lister.rb:41-42`) верна; это лишь усиление покрытия.

## Residual risks

- **O(n) скан архива на каждый `aggregate-status`-вызов**: `Archive::Api.list`
  читает каждый архивный `task.yaml`. На текущем масштабе (десятки задач) дёшево;
  на больших архивах — кандидат на индексацию (зафиксировано в design/brief как
  будущая оптимизация, не баг).
- **Прогресс архивных детей** в `by_child` отдаётся как `empty_progress`
  (`children_lister.rb:66, 100-102`). Для расчёта гейта это безвредно
  (`child_state` шорткатит по `status`), но потребитель, читающий
  `progress` архивного ребёнка, увидит `0/0` вместо реального — косметическое
  ограничение, не влияющее на корректность.
- **Зависимость ленивого require от порядка загрузки**: устранена тем, что вызов
  происходит в рантайме после полной загрузки; подтверждено симуляцией и зелёным
  полным suite. Риск остаточный-нулевой при текущей структуре require.
