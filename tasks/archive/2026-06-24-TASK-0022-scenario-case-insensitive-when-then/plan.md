# Goal

Сделать `WhenThenChecker` регистронезависимым по ключевым словам WHEN/THEN и выдавать
информативное сообщение об отсутствующей клаузе, показывающее ожидаемый формат строки.

# Scope

- `lib/owl/validation/internal/when_then_checker.rb`: `/i` на `CLAUSE_RES`, обновлённый
  текст `violation`.
- Тесты валидатора (Title/lower/UPPERCASE кейсы + текст сообщения).
- Bump `Owl::VERSION` (minor — смягчение контракта) + CHANGELOG.

# Constraints

- Ослабить ТОЛЬКО чувствительность к регистру ключевого слова; сохранить структурные
  проверки (наличие `#### Scenario:`, наличие обеих клауз) и толерантность к префиксам
  `>`/`*`/`-`/пробелам.
- Обратная совместимость: UPPERCASE `- WHEN`/`- THEN` остаётся валидным.
- Сообщение об ошибке — не ломать другие компоненты, которые могут проверять
  `type: 'scenario_missing_clause'` (менять `description`, не `type`).

# Checklist

1. В `CLAUSE_RES` добавить флаг `i`:
   `'WHEN' => /\A[\s>*-]*\**\s*WHEN\b/i`, `'THEN' => /\A[\s>*-]*\**\s*THEN\b/i`.
   (Структура `SCENARIO_RE` не трогается — заголовок `Scenario` уже фиксированного
   регистра по шаблону; при желании оценить, не нужна ли и ему толерантность, но это
   вне минимального fix.)
2. Обновить `violation` (`description`): с `"Scenario '…' is missing a #{keyword}
   clause."` на информативное, напр.: `"Scenario '…' is missing a #{keyword} clause —
   expected a line like '- #{keyword} …' (case-insensitive) inside the '#### Scenario:'
   block."` Сохранить ключ `type: 'scenario_missing_clause'` и поле `keyword`.
3. Тесты `spec/owl/validation/...when_then...`: добавить кейсы — Title-case `- When/-
   Then` проходит, lower-case проходит, UPPERCASE остаётся валидным; обновить
   ассерты на текст сообщения (если завязаны на старую строку).
4. Проверить, нет ли в проекте/шаблонах прямой зависимости на старый текст сообщения
   (grep), обновить при необходимости.
5. Bump `Owl::VERSION` (minor) + `CHANGELOG.md`.

# Files to inspect

- `lib/owl/validation/internal/when_then_checker.rb` — основной fix.
- `lib/owl/validation/internal/artifact_runner.rb` — как вызывается checker (контекст).
- `spec/owl/validation/**` — тесты валидатора (найти существующий when_then спек).
- `lib/owl/version.rb`, `CHANGELOG.md`.

# Tests and verification

- Юнит: Title-case и lower-case сценарии валидны; UPPERCASE валиден; отсутствие клаузы
  даёт сообщение с ожидаемым форматом.
- `bundle exec rspec` зелёный (после — `git checkout README.md`).
- 100% покрытие затронутых `**/api.rb` (валидатор внутренний; `validation/api.rb` если
  затронут — покрыть); RuboCop net-zero на трогаемых файлах.

# Smoke test

```
# brief с `- When …` / `- Then …` (Title-case) в #### Scenario:
owl artifact validate <TASK> brief --json   # → valid:true
# brief со сценарием без THEN:
owl artifact validate <TASK> brief --json   # → сообщение показывает ожидаемый формат
```

# Out of scope

- Доставка grammar-doc (TASK-0020).
- Прочие PF-фиксы CLI (TASK-0023), brief-body/overlays (TASK-0024).
