---
status: approved
summary: >-
  Декомпозиция кросс-задачной памяти `owl recall`. По явному решению автора
  фича НЕ дробится на несколько детей: composite-родитель TASK-0015 порождает
  ровно одного ребёнка TASK-0018 (feature-workflow), несущего всю фичу целиком
  (движок Owl::Recall + CLI `owl recall` + surface на шаге brief). Родитель
  ждёт ребёнка (archive/commit_push gated children_complete) и архивируется
  вместе с ним.
---

# Decomposition — `owl recall` (кросс-задачная память)

## Goal

Доставить фичу `owl recall` целиком, сохранив composite-машинерию родителя, но
без искусственного дробления. Автор явно выбрал «не делить» (см. интерактивный
чекпоинт decompose): движок, CLI-команда и surface на brief достаточно связаны
и невелики, чтобы один независимо поставляемый ребёнок реализовал их вместе под
единым API-контрактом из родительского `design`.

## Children

### TASK-0018 — `owl recall`: лексическая кросс-задачная память (движок + CLI + surface)

- **Workflow:** `feature` (полный: design → plan → implement → review →
  merge_docs → archive → commit_push). Ребёнок стартует с `design` (его brief
  предзаполнен родительским и помечен done).
- **Scope (вся фича):**
  1. **Движок `Owl::Recall`** — `lib/owl/recall/api.rb`
     (`Owl::Recall::Api.recall(root:, query:, limit:)`) + `internal/`
     (`tokenizer`, `corpus_builder` поверх `Owl::Archive::Api.list|read`,
     `scorer` — tf-idf/token-overlap, чистый Ruby). 100% покрытие api.rb.
  2. **CLI `owl recall`** — `lib/owl/cli/internal/commands/recall.rb`,
     регистрация `'recall' => :dispatch_recall` в `lib/owl/cli/api.rb`, usage в
     `help_text.rb`, JSON-контракт `{ok, matches:[{task_id,title,score,snippet}]}`,
     `--limit`/`--root`/`--json`. minor-бамп `Owl::VERSION` + CHANGELOG.
  3. **Surface на шаге brief** — owl-step-discussion вызывает `owl recall
     "<title>"` и рендерит «Похожие архивные задачи»; пустой результат явно
     сообщается, шаг не блокируется.
- **Brief/Design ребёнка:** brief предзаполнен из родительского (полный спек
  фичи); общий API-контракт зафиксирован в родительском `design.md` и наследуется.
- **Независимая поставляемость:** да — ребёнок самодостаточен, проходит весь
  feature-workflow и поставляет рабочую команду + surface.

## Order

1. **TASK-0018** — единственный ребёнок; порядок внутри него задаётся его
   собственным `plan` (ожидаемо: движок → CLI → surface, т.к. CLI зависит от
   движка, а surface — от CLI).

Родитель TASK-0015: шаг `review` (ungated) валидирует саму декомпозицию и может
пройти сразу; шаги `archive` и `commit_push` gated `children_complete` —
родитель намеренно паузится, пока TASK-0018 не дойдёт до ready/archived, затем
архивируется атомарно вместе с поддеревом.
