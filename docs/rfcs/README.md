# Owl RFCs

Архитектурные решения и контракты Owl, требующие нормативной точки опоры. Каждый RFC — отдельный документ; статусы движутся `Draft → Accepted → Superseded`.

| #    | Title                                                                       | Status   | Created    |
| ---- | --------------------------------------------------------------------------- | -------- | ---------- |
| 0001 | [Session-typed steps and subagent contract](0001-session-typed-steps.md)    | Accepted | 2026-05-24 |

## Conventions

- **File name:** `<number>-<kebab-title>.md`. Номер — четыре цифры, начинается с `0001`.
- **Frontmatter (required):** `number`, `title`, `status`, `authors`, `created`. **Optional:** `slug`, `knowledge_entry_id` (cross-link с KOS knowledge), `superseded_by` (для статуса `Superseded`).
- **Status lifecycle:**
  - **Draft** — в разработке, не нормативный. Ссылки из кода допустимы, но помечаются как «provisional».
  - **Accepted** — нормативный документ, описывает реализованное поведение. Ссылки из кода/тестов идут на разделы RFC напрямую.
  - **Superseded** — заменён более новым RFC; в frontmatter добавляется `superseded_by: <number>`; тело файла остаётся для исторического контекста.
- **Изменения контракта** оформляются **новыми** RFC, ссылающимися на предшественника. Старый RFC переходит в `Superseded`. Существенные правки в самом теле `Accepted` RFC требуют отдельной KOS-задачи и поля `last_revised` в frontmatter.
- **Implementation anchors.** «Горячие» нормативные секции (те, на которые ссылаются код и спецификации) должны содержать прямые ссылки на `lib/owl/<path>.rb:N` под заголовком **Implementation anchors**, чтобы рассинхрон с кодом замечался при чтении.

## Cross-references

- Owl Project Constitution (KOS knowledge article 23) задаёт source-of-truth-иерархию и опускает технические инварианты в RFC.
- KOS knowledge article 46 (`Owl architecture RFC: session-typed orchestration`) — исходный source-of-truth для RFC #1. После публикации этого каталога KOS-статья остаётся синонимом, файл репо — публичной поверхностью.
