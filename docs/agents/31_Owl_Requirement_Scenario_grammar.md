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

## 3a. Аннотация `- TEST:` (трассировка scenario → test)

Чтобы «green verification» давал сильную гарантию соответствия спецификации,
каждый `#### Scenario:` несёт одну или несколько строк `- TEST: <ссылка>`,
называющих проверяющий его тест. Это сиблинг клауз `- WHEN` / `- THEN` внутри
блока сценария.

```
#### Scenario: <имя случая>
- WHEN <триггер>
- THEN <ожидаемый результат>
- TEST: spec/owl/specs/trace_spec.rb
- TEST: ещё один проверяющий пример — опционально
```

- **Синтаксис.** Маркер `TEST:` пишется заглавными в начале пункта списка;
  допускаются ведущие `-`/`*`/`>` и `**` (жирный) и отступ — толерантность та же,
  что у WHEN/THEN (regex `/^[\s>*-]*\**\s*TEST:\s*(.+?)\s*$/`).
- **Ссылка** — свободный текст: путь к файлу теста
  (`spec/owl/specs/foo_spec.rb`), описание примера или id.
- **≥1 `- TEST:` на сценарий** требуется для полной трассируемости. Сценарий без
  `- TEST:` помечается как `untraced`.
- **Классификация ссылок** чекером `owl spec trace`:
  - *path-like* (содержит `/` и заканчивается на `.<ext>`) → проверяется наличие
    файла под корнем проекта: есть → `traced`, нет → `dangling`;
  - не-path (проза/id) → `unverified` (засчитывается как traced для `valid`, но
    выводится для ручного аудита).
- **Enforcement.** Это **не** authoring-time-валидация: `owl spec validate` и gate
  шага `complete` не требуют `- TEST:` (черновик спецификации может появиться
  раньше тестов). Гейт — `owl spec trace <domain> --strict`, который возвращает
  `ok:false` (exit 1) при любом `untraced`-сценарии или `dangling`-ссылке.
  Предполагаемое место запуска — шаг `verification` рабочего процесса `feature`
  (`owl spec trace <domain> --strict`); проводка этого в YAML рабочего процесса
  отложена намеренно (как в P4) и authoring-time-валидация остаётся неизменной.

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
