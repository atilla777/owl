---
status: resolved
summary: >-
  owl recall реализован по контракту design.md: чистый tf-idf-движок поверх
  Owl::Archive::Api, CLI с JSON {ok,matches}, 100% покрытие recall/api.rb,
  surface на brief тонкий и не блокирующий. Найденный ревью edge
  (отрицательный --limit ронял команду трассой) исправлен в этом же шаге:
  limit клампится к 0, спека добавлена.
verdict: accepted
ready: true
---

# Code review — `owl recall` (TASK-0018)

## Summary

Независимый ревью рабочего дерева, реализующего `owl recall` (кросс-задачная
лексическая память). Реализация соответствует `brief.md` и `design.md`:

- `Owl::Recall::Api.recall(root:, query:, limit:)` возвращает
  `Array<{task_id,title,score,snippet}>`, отсортированный по `score` desc,
  затем `task_id` asc, усечённый до `limit`; пустой/стоп-словный запрос,
  пустой архив и отсутствие совпадений дают `[]` (api.rb:25–33).
- Слой соблюдён: корпус строится только через `Owl::Archive::Api.list/read`
  (`corpus_builder.rb`); прямых `File.`/`Dir.`/`Pathname`/`tasks/archive`
  обращений в `lib/owl/recall/**` нет (grep дал только совпадение в
  комментарии).
- CLI `owl recall` печатает `{ok:true, matches:[...]}`; пустой запрос →
  `{ok:true,matches:[]}` exit 0, без трассы (recall.rb).
- Версия поднята minor `0.5.0 → 0.6.0`, есть запись в `CHANGELOG.md` тем же
  изменением (Конституция §7.1).
- `skills/owl-step-discussion/SKILL.md` и его материализованная копия
  `.claude/skills/owl-step-discussion/SKILL.md` идентичны (`owl upgrade`
  прогнан); surface только зовёт `owl recall`, скоринг не дублирует, шаг не
  блокируется при пустом/ошибочном recall.

Контракт, слой, покрытие и версия — в порядке. Один edge-case вне перечня
acceptance-criteria (отрицательный `--limit`) был найден ревью и **исправлен в
этом же шаге** (loop-back в implement), а не вынесен в follow-up.

## Findings

### F1 — [low] Отрицательный `--limit` ронял команду стек-трейсом → ИСПРАВЛЕНО

Исходно `bin/owl recall "spec validation" --limit -1 --json` падал с
`ArgumentError: negative array size` (`scorer.rb:30` → `scored.first(limit)`
при `limit < 0`). Трасса уходила пользователю — противоречие docstring'у
команды «it never crashes» и духу brief'а «не падать трассой».

**Исправление (в этом шаге):** `Owl::Recall::Api.recall` клампит лимит
`capped = [limit.to_i, 0].max` перед передачей в `Scorer.rank` (api.rb), так
что отрицательный лимит даёт `[]`, а не исключение. Добавлена спека
«clamps a negative limit to 0 instead of raising» (`api_spec.rb`).
Проверено смоуком: `bin/owl recall "semantic" --limit -1 --json`
→ `{ok:true,matches:[]}` exit 0. Клампинг в Api защищает и CLI, и surface.

### F2 — [info] Сниппет фактически = начало документа, а не «совпавшая строка»

`CorpusBuilder.extract_sections` склеивает все строки Problem/Goal в одну
через пробел, а `text = "#{title} #{brief_text}"`. Поэтому в `text`
практически одна логическая строка, и `Scorer.matching_line` почти всегда
возвращает её начало (с title впереди). На смоук-выводе сниппеты выглядят как
«Title + начало brief», усечённые до 140. Контракт это НЕ нарушает: сниппет
одно-строчный, ≤140 симв., схлопнутые пробелы, JSON-safe (подтверждено
смоуком и спекой `ranking_spec.rb`). Это качество подсветки, а не баг.

### F3 — [info] Покрытие 100% и тестовое качество — подтверждено

`lib/owl/recall/api.rb` покрыт 14/14 строк (0 пропусков), что удовлетворяет
`docs/agents/30_...`. Спеки реально проверяют: порядок ранжирования
(`api_spec`, `ranking_spec`), детерминизм и tie-break по `task_id` asc
(`ranking_spec`), кириллическую токенизацию и ранжирование (`ranking_spec`),
корпус только из архива + доступ через `Archive::Api` через мок
`have_received(:list/:read)` (`corpus_spec`), задачу без brief (fallback на
title), только Problem/Goal в тексте, limit, пустой запрос, стоп-слова,
пустой архив, отсутствие совпадений, форму JSON CLI и `invalid_arguments` на
битом `--limit`. Покрытие acceptance-criteria — полное.

## Resolution

- **F1** — ИСПРАВЛЕНО в этом шаге (клампинг лимита в `Api.recall` + спека);
  полный прогон зелёный (1741 examples, 0 failures). Не остаётся follow-up'ом.
- **F2** — принято как есть; контракт сниппета соблюдён, улучшение подсветки —
  опциональный косметический follow-up.
- **F3** — претензий нет, требование покрытия выполнено.

## Remediation

- F1 устранён непосредственно (см. Findings). Отдельной задачи не требуется.
- Опционально к F2: строить сниппет из первой строки именно brief-секции
  (без title-префикса), если нужно более релевантное превью.

## Residual risks

- Качество ранжирования на больших корпусах не нагрузочно-тестировалось;
  на текущем масштабе (десятки архивных задач) прямой проход дёшев и
  детерминирован — соответствует non-goal'ам brief'а.
- Сниппет-подсветка не таргетирует точный совпавший терм (F2) — косметика.
