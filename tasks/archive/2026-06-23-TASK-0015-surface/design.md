---
status: approved
summary: >-
  Архитектурный baseline кросс-задачной памяти `owl recall`. Новый модуль
  `Owl::Recall` (Api + internal: tokenizer / corpus_builder / scorer), который
  читает корпус архивных задач ИСКЛЮЧИТЕЛЬНО через `Owl::Archive::Api`
  (list/read), считает лексический score (tf-idf на token-overlap, чистый
  Ruby) и возвращает ранжированные matches. CLI-команда `owl recall` живёт в
  `lib/owl/cli/internal/commands/recall.rb` и регистрируется в dispatch-таблице.
  Surface на шаге brief — тонкий вызов `owl recall <title>` из
  owl-step-discussion. Контракт `Owl::Recall::Api.recall` и JSON-форма
  `{ok, matches:[{task_id,title,score,snippet}]}` — общий инвариант для всех
  детей декомпозиции.
---

# Design — Кросс-задачная память `owl recall`

## Context

Owl уложен слоями `Backend → Internal → Api` помодульно: каждая фича — каталог
`lib/owl/<feature>/` с публичным `api.rb` и приватным `internal/`. Доступ к ФС
инкапсулирован в Internal; Api/CLI к файлам напрямую не ходят
(`docs/agents/27_Owl_Ruby_code_architecture.md`).

Релевантные существующие точки:

- **`Owl::Archive::Api`** (`lib/owl/archive/api.rb`) — уже даёт
  `list(root:)`, `show(root:, task_id:)`, `read(root:, task_id:, artifact_key:)`
  над archive-ролью (`tasks/archive/**`). Это готовый и единственный
  легальный шлюз к корпусу архивных задач — `recall` строится поверх него,
  не дублируя чтение ФС.
- **CLI** (`lib/owl/cli/api.rb`) — таблица `dispatch_*` + per-command файлы в
  `lib/owl/cli/internal/commands/<name>.rb`; usage-строки в
  `lib/owl/cli/internal/help_text.rb`. Команды эмитят JSON через общий
  `Owl::Result`/result-обёртку.
- **Шаг `brief`** исполняется `owl-step-discussion` в основной сессии — место,
  где результат `recall` показывается автору.

`brief` (этой задачи) зафиксировал: лексический поиск, новая команда
`owl recall`, корпус = только архив, вывод = ранжированный список + сниппет.
Этот design фиксирует, КАК это разложено по слоям, чтобы дети декомпозиции
делили один контракт.

## Decision

Ввести новый модуль **`Owl::Recall`** со стандартной раскладкой Api+internal и
тонкую CLI-обёртку. Границы:

1. **`lib/owl/recall/api.rb` — `Owl::Recall::Api`** (публичный контракт,
   100% покрытие строк по
   `docs/agents/30_Owl_Ruby_testing_RSpec_and_public_API_coverage.md`):
   - `recall(root:, query:, limit: DEFAULT_LIMIT)` →
     `[{ task_id:, title:, score:, snippet: }, ...]` (Ruby-объекты,
     отсортированы по убыванию `score`, при равенстве — вторичный ключ
     `task_id` для детерминизма). Api **не** печатает и не знает про JSON.
2. **`lib/owl/recall/internal/`** — реализация (приватная, ходит к данным
   только через `Owl::Archive::Api`):
   - `corpus_builder.rb` — `Owl::Archive::Api.list(root:)` → для каждой
     архивной задачи собрать документ: `title` + секции `Problem`/`Goal` из
     `brief` (через `Owl::Archive::Api.read(.., 'brief')`; задача без brief →
     документ только из `title`). Никаких прямых `File.read`.
   - `tokenizer.rb` — нормализация (downcase, юникод/кириллица), разбиение на
     токены, отбрасывание стоп-слов/пустых.
   - `scorer.rb` — tf-idf поверх token-overlap запрос↔документ; чистый Ruby,
     без сети и новых gem-ов; плюс выбор `snippet` (1-строчный усечённый
     фрагмент документа вокруг совпавших термов, безопасный для JSON).
3. **`lib/owl/cli/internal/commands/recall.rb`** — парсит
   `owl recall <query> [--json] [--limit N] [--root PATH]`, зовёт
   `Owl::Recall::Api.recall`, сериализует в
   `{ok: true, matches: [{task_id, title, score, snippet}]}`. Регистрация:
   `'recall' => :dispatch_recall` в `lib/owl/cli/api.rb` + usage в
   `help_text.rb`. Команда **read-only** (никаких мутаций состояния).
4. **Surface на brief** — тонкая правка `owl-step-discussion`
   (skills/owl-step-discussion): на шаге `brief` вызвать `owl recall "<title>"`
   и показать секцию «Похожие архивные задачи»; пустой результат — явное
   сообщение, шаг не блокируется. Логика ранжирования здесь не дублируется —
   только вызов CLI и рендер.

**Версия/чейнджлог:** новая команда = **minor**-бамп `Owl::VERSION` + запись в
`CHANGELOG.md` в том же коммите (Конституция §7.1). Этот пункт несёт ребёнок,
завершающий CLI-поверхность (или общий terminal-ребёнок).

## Alternatives

- **Прямое чтение `tasks/archive/**` в recall.** Отвергнуто: нарушает
  source-of-truth/слой Backend (overlay чек-лист brief). `Owl::Archive::Api`
  уже даёт ровно нужный доступ.
- **Семантический поиск (embeddings/API).** Отвергнут на этапе brief: сетевая
  зависимость, ключи, кэш эмбеддингов — избыточно для десятков задач.
- **Персистентный индекс на диске.** Отложено: на текущем масштабе прямой
  проход по корпусу при каждом вызове дёшев; индекс — будущая оптимизация за
  стабильным Api-контрактом, не ломающая его.
- **Авто-инъекция «Related prior work» прямо в bundle `owl step show`.**
  Отвергнута на этапе brief в пользу явной команды + тонкого surface: связывать
  retrieval с движком шагов нежелательно; команда переиспользуема и тестируема
  отдельно.
- **Команда внутри `Owl::Archive`** (`owl archive recall`). Отвергнуто: recall —
  отдельная ответственность (ранжирование), чище как самостоятельный модуль
  `Owl::Recall`, потребляющий Archive::Api.

## Risks

- **Качество лексического ранжирования** (короткие запросы, синонимы). Митигация:
  tf-idf + нормализация; принять как осознанный компромисс (не семантика);
  покрыть ranking-спеками на показательных кейсах.
- **Кириллическая токенизация.** Заголовки/брифы проекта на русском — риск
  кривой нормализации. Митигация: явные спеки на кириллицу (edge case в brief).
- **Связанность surface↔CLI.** owl-step-discussion должен лишь *звать* `owl
  recall`, не парсить архив сам. Митигация: surface — тонкий, без логики
  скоринга; контрактный тест на секцию «Похожие архивные задачи».
- **Backward-compat CLI-контракта.** JSON-форма `recall` становится публичным
  контрактом. Митигация: зафиксировать форму в design (ниже) и в спеках; любые
  будущие изменения формы — по правилам SemVer Конституции.
- **Стабильность вывода.** Недетерминизм при равных score сломает
  воспроизводимость/тесты. Митигация: вторичный ключ сортировки `task_id`.

## API

Контракт, который наследуют все дети декомпозиции (менять только согласованно):

**Ruby (внутренний публичный):**

```
Owl::Recall::Api.recall(root:, query:, limit: DEFAULT_LIMIT)
  # => Array<Hash> отсортированный по score desc, затем task_id asc:
  #    [{ task_id: "TASK-0007", title: "...", score: 0.82, snippet: "..." }, ...]
  # query пустой/только стоп-слова  => []
  # архив пуст / нет совпадений      => []
  # доступ к корпусу ТОЛЬКО через Owl::Archive::Api (list/read)
```

**CLI:**

```
owl recall <query> [--limit N] [--root PATH] [--json|--no-json]
```

**JSON (по умолчанию):**

```json
{ "ok": true,
  "matches": [
    { "task_id": "TASK-0007", "title": "Wire spec layer ...",
      "score": 0.82, "snippet": "...совпавший фрагмент..." }
  ] }
```

- `matches` отсортирован по `score` desc, вторично `task_id` asc.
- `--limit N` усекает до топ-N (по умолчанию `DEFAULT_LIMIT`, напр. 10).
- Пустой корпус / нет совпадений → `{ "ok": true, "matches": [] }`, exit 0.
- Пустой/тривиальный запрос → `matches: []` (или валидационная ошибка с понятным
  `error.code`); команда не падает трассой.
- Команда **read-only**: не пишет/не мутирует репозиторий.

**Surface (шаг brief, owl-step-discussion):** вызывает `owl recall "<task.title>"
--json`, рендерит топ-совпадения как «Похожие архивные задачи»
(`task_id` · `title` · `snippet`); пустой результат — явная строка «похожих не
найдено», без блокировки шага.

**Декомпозиция (ориентир для `decompose`, не обязывающий):**
(a) движок `Owl::Recall` (tokenizer + corpus_builder поверх Archive::Api +
scorer) с api/ranking/corpus-спеками; (b) CLI-команда `owl recall` + регистрация
+ help + JSON-контракт + version/CHANGELOG-бамп; (c) surface на шаге `brief` в
owl-step-discussion + контрактный тест. Точные границы — за `decompose`.
