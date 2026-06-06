# Owl Requirement/Scenario grammar

Extends [[owl-project-constitution]] §5.16.
Sibling rules: [[owl-ruby-code-architecture]], [[owl-ruby-testing-rspec-and-public-api-coverage]].

---

# Owl Requirement/Scenario grammar

## 1. Назначение

Зафиксировать единую формальную грамматику пользовательских сценариев — пара
`### Requirement:` / `#### Scenario:` с нормативным RFC 2119-предложением и
клаузами WHEN/THEN. Это канонический справочник, на который ссылаются шаблоны
артефактов `brief` и `spec`. Цель — чтобы один и тот же сценарий читался
одинаково любым агентом и человеком и был проверяемым контрактом, а не свободной
прозой.

## 2. Грамматика

Сценарии живут под секцией `## Scenarios` (в `brief`) или `## Requirements`
(в `spec`) и состоят из блоков:

```
### Requirement: <краткое имя поведения>

The system SHALL <одно нормативное предложение>.

#### Scenario: <краткое имя случая>
- WHEN <триггер или предусловие>
- THEN <ожидаемый наблюдаемый результат>
- AND <дополнительный наблюдаемый результат — опционально>
```

- **`### Requirement: <name>`** (heading level 3) — формулирует **одно**
  нормативное утверждение ровно одним RFC 2119-ключевым словом:
  `SHALL` / `MUST` (обязательно), `SHOULD` (рекомендуется), `MAY`
  (разрешено). Для регрессий допустимо `SHALL NOT`. Одно требование — одно
  предложение; несколько поведений → несколько `### Requirement`.
- **`#### Scenario: <name>`** (heading level 4) — конкретный проверяемый случай
  под требованием. Клаузы оформляются маркерами списка:
  - **`- WHEN`** — триггер/предусловие (обязательно);
  - **`- THEN`** — ожидаемый наблюдаемый результат (обязательно);
  - **`- AND`** — дополнительные клаузы (опционально), читаются как продолжение
    предыдущего WHEN или THEN.

## 3. Правила

1. **Каждое `### Requirement` имеет ≥1 `#### Scenario`.** Требование без
   сценария — неполный контракт.
2. **Каждый `#### Scenario` содержит и WHEN, и THEN.** Сценарий без одного из
   них не описывает проверяемого поведения.
3. **Заголовок Requirement несёт ровно одно нормативное предложение** с одним
   RFC 2119-ключевым словом — без «и/или», связывающих два требования в одно.
4. Маркеры `WHEN`/`THEN`/`AND` пишутся заглавными в начале пункта списка;
   допускаются ведущие `-`/`*`/`>` и `**` (жирный) — чекер их толерирует.

## 4. Где это применяется (enforcement)

Грамматика — не соглашение «на честном слове», она проверяется существующими
ключами валидации в определении типов артефактов (`artifact.yaml`):

| Ключ | Что проверяет | Тип артефакта |
| --- | --- | --- |
| `required_patterns` (regex `(?m)^###\s+Requirement:`) | тело содержит ≥1 формальный `### Requirement:` → иначе блокирующий `missing_pattern` | `brief` |
| `require_scenarios: true` | у каждого `### Requirement` есть `#### Scenario` → иначе `requirement_without_scenario` | `brief`, `spec` |
| `require_when_then: true` | у каждого `#### Scenario` есть и WHEN, и THEN → иначе `scenario_missing_clause` | `brief`, `spec` |

Эти ключи читает `Owl::Validation::Internal::ArtifactRunner` (чекеры
`PatternsChecker`, `ScenariosChecker`, `WhenThenChecker`). Нарушения с
`level: error` блокируют `owl artifact validate` и gate шага `complete`.

`brief` **не** включает `forbid_empty_sections` — требование может не нести
прозы между заголовком и сценарием.

## 5. Пример

```
### Requirement: Briefs must contain a well-formed Requirement

The system SHALL reject a brief that has no `### Requirement:` heading.

#### Scenario: Prose-only brief is rejected
- WHEN a brief's Scenarios section is free prose with no `### Requirement:` heading
- THEN `owl artifact validate <task> brief` reports a blocking `missing_pattern` violation
- AND the step `complete` gate refuses until a formal Requirement is added
```
