---
status: shipped
summary: "Реализовать flip approved→shipped в publish-пайплайне (flip источника ДО копии, чтобы копия несла shipped), добавить генерируемый docs/README.md-индекс как пост-шаг publish (Internal::DocsIndex, скан docs/<TASK>/ через Storage, детерминированно), и привести прозу merge_docs/publish к реальности. Контракт owl publish расширяется аддитивно. step-id merge_docs не трогаем; KB не строим."
---

# Design: merge_docs/publish — честность + индекс + shipped-flip

## Context

Текущий publish-пайплайн (`lib/owl/publish/...`):

- `Owl::Publish::Api.run(root:, task_id:, dry_run:, now:)`
  (`lib/owl/publish/api.rb:18`) → backend `Publish::Backends::Filesystem#run`
  (`lib/owl/publish/backends/filesystem.rb:22`): StepGate → RulesLoader →
  PathResolver → `Publisher.call`.
- `Publisher` (`lib/owl/publish/internal/publisher.rb`) для каждого правила:
  читает источник, при наличии target делает `.bak-<ts>` бэкап, копирует через
  `Owl::Storage::Api.read/write`. Действия: `created` / `replaced` /
  `skipped_missing_source`; ошибки `source_missing` / `write_failed` /
  `backup_failed`. **Никакой мутации front-matter** — копия as-is.
- Результат: `{ ok, task_id, workflow_key, dry_run, step_status, results:[...] }`.
- `merge_docs.context.md` обещает flip `approved→shipped` (не реализовано) и
  описывает шаг как «merge published docs» (overselling).
- `docs/` — per-task копии `design.md`, без индекса.

Артефакт `design` имеет front-matter `status: draft|approved|shipped`
(шаблон design). Front-matter повсеместно парсится internal-утилитами
(`lib/owl/artifacts/...`, `lib/owl/steps/internal/...`). `Owl::Storage::Api`
— санкционированный слой доступа к файлам.

Бриф зафиксировал направление (честно упростить, не KB), сохранение step-id и
реализацию flip. Дизайн закрывает: (1) где/как выполнять flip и в каком порядке
с копией; (2) как и когда строить индекс; (3) объём правок прозы; (4)
аддитивность контракта.

## Decision

**1. shipped-flip — в backend `Publish::Backends::Filesystem#run`, ПОСЛЕ
PathResolver и ДО (или вокруг) копии, по правилам, чей источник —
`design.md`.** Вводим `Owl::Publish::Internal::StatusFlipper`:
- читает источник правила, парсит front-matter; если это `design` со статусом
  `approved` → переписывает `status: shipped` в **каноничном источнике**
  `tasks/<ID>/design.md` через `Storage::Api`, затем `Publisher` копирует уже
  `shipped`-версию в `docs/<ID>/design.md`. Так source и копия согласованы одним
  действием, без двойной правки.
- Применяется только при non-dry-run и только если источник существует
  (optional-missing → пропуск). Идемпотентно: `shipped`/нет front-matter →
  no-op.
- Какие правила «design-подобные»: критерий — целевой артефакт правила имеет
  front-matter со `status`-полем enum, включающим `shipped` (обобщённо), а не
  хардкод имени файла. Практически срабатывает на `design.md`.

**2. Индекс — пост-шаг publish, новый `Owl::Publish::Internal::DocsIndex`.**
После успешной (non-dry-run) копии backend вызывает `DocsIndex.regenerate`:
- сканирует `docs/` на каталоги `TASK-*/` через `Storage::Api`, собирает
  опубликованные файлы, формирует детерминированный `docs/README.md`
  (сортировка по TASK-ID; для каждого — ссылка(и) на опубликованные доки и,
  если доступно, `summary` из front-matter).
- Идемпотентно: одинаковый набор доков → побайтно одинаковый README. dry-run →
  не пишет. Перезапись существующего `docs/README.md` — с тем же `.bak-<ts>`
  поведением, что у Publisher (через общий backup-хелпер).
- Индекс **агрегирует все** существующие `docs/TASK-*/`, а не только текущую
  задачу (скан, не инкремент) → устойчив к ручным правкам/удалениям.

**3. Проза.** Переписать описания под реальность (без «merge»/«knowledge
base»): источник `workflows/feature/merge_docs.context.md` + материализованные
`.owl/workflows/{feature,hotfix,refactor}/merge_docs.context.md`; упоминания в
`skills/owl-step-execution/SKILL.md` и `skills/_owl_conventions.md`/
`owl-orchestrator` при наличии; пользовательские доки (`README.md`,
`REQUIREMENTS.md`, `ARCHITECTURE.md`, `AGENTS.md`, `CLAUDE.md`) — точечно, только
там, где есть overselling. Описать реально реализованные flip и индекс.
`bin/owl upgrade` синкнет `.claude/` зеркала в commit_push.

**4. Контракт `owl publish --json` — аддитивно.** В результат добавляются
необязательные сведения: `design_status` (напр. `flipped_to_shipped` |
`already_shipped` | `not_applicable`) и `index` (`{updated: bool, path:
"docs/README.md"}`). Существующие ключи (`results[].action`, `step_status`,
`dry_run`) не меняются → bump **minor**.

**5. step-id `merge_docs` сохраняем; KB не строим.** Честность через прозу +
bugfix + лёгкий индекс. spec-слой и TASK-0015 остаются носителями «знаний».

## Alternatives

1. **Flip ПОСЛЕ копии, патчить и source, и target отдельно.** Две записи,
   риск рассинхрона и лишний diff. Отвергнут в пользу «flip source → copy».

2. **Flip только в опубликованной копии, source оставить `approved`.** Тогда
   каноничный артефакт задачи не отражает «shipped», что и есть исходное
   обещание контекста (статус артефакта = состояние дизайна). Отвергнут:
   `shipped` — это состояние артефакта, а не копии.

3. **Индекс отдельной командой `owl docs index` (ручной/CI).** Гибко, но
   расходится с целью «findability из коробки» и требует помнить запуск.
   Авто-регенерация в publish проще для пользователя. (Команду можно добавить
   как тонкую обёртку поверх `DocsIndex` позже — out of scope.)

4. **Инкрементальный индекс (дописывать строку про текущую задачу).** Ломается
   при ручных удалениях/переименованиях и не идемпотентен. Полный
   скан-и-перегенерация надёжнее. Отвергнут.

5. **Полноценный KB (агрегация/поиск/`owl docs` browse).** Большой объём,
   дублирует spec-слой и TASK-0015. Отвергнут на брифе.

6. **Массовый ренейм step-id `merge_docs → publish_docs`.** Breaking (on-disk
   формат, архивные task.yaml, JSON-контракт), ~70 файлов, переписывание истории
   dogfood-репо. Цена>польза. Отвергнут на брифе.

## Risks

- **Регрессия publish-контракта.** Новые ключи должны быть строго аддитивны;
  существующие специи (`spec/owl/publish/*`, integration full-cycle) — зелёные.
  Митигировать тестами на неизменность `results`/`action`.
- **Порядок flip/copy.** Если flip упадёт, копировать нельзя (иначе копия
  `approved`, source `shipped` — рассинхрон). flip и copy должны быть
  последовательны с возвратом `Err` при сбое flip до копии.
- **dry-run чистота.** И flip, и индекс обязаны быть no-op при dry-run; иначе
  «превью» мутирует репо. Явные тесты.
- **Идемпотентность индекса.** Недетерминированный порядок/таймстемпы в README
  дадут «грязный» git каждый publish. Сортировать детерминированно, без
  таймстемпов в теле индекса.
- **Бэкапы `.bak`.** docs/README.md перезаписывается часто → может плодить
  бэкапы. Решение: для генерируемого индекса бэкап можно не делать (он
  воспроизводим из docs/), но это решение зафиксировать тестом/прозой.
- **100% покрытие `lib/owl/publish/api.rb`.** Новые ветки (flip/index, dry-run,
  no-source) должны быть покрыты построчно.
- **Проза vs материализация.** Правка только source-`workflows/*` без
  `.owl/workflows/*` (или наоборот) даст расхождение; править оба + `upgrade`.

## API

Публичная поверхность (публикуется при merge_docs):

**Поведение `owl publish TASK-ID [--dry-run] [--json]`** (контракт расширен):
- Side effects (non-dry-run): `design` источника `approved→shipped`;
  `docs/<ID>/design.md` несёт `shipped`; `docs/README.md` (пере)генерирован.
- JSON-результат: существующие ключи без изменений + добавлены
  `design_status: "flipped_to_shipped"|"already_shipped"|"not_applicable"` и
  `index: { updated: bool, path: "docs/README.md" }`.
- dry-run: ничего не пишет (ни flip, ни индекс, ни копии).

**Сгенерированный артефакт**
- `docs/README.md` — индекс опубликованных доков (ссылки + summary),
  детерминированный, идемпотентный.

**Внутренние модули (Ruby, не публичный API)**
- `Owl::Publish::Internal::StatusFlipper` — flip front-matter источника.
- `Owl::Publish::Internal::DocsIndex` — скан `docs/TASK-*/` + рендер README.

**Без изменений контракта**: `results[].action`
(`created|replaced|skipped_missing_source`), коды ошибок
(`source_missing|no_publishable_step|write_failed|backup_failed`),
`owl spec merge` (`no_spec_delta` и пр.), step-id `merge_docs`.

**Проза** (поведенческая документация, не код-контракт): контекст шага и
скиллы/доки описывают «публикацию артефактов в `docs/` + опциональный
`spec_delta` + flip `shipped` + генерируемый индекс», без «merge»/«база знаний».
