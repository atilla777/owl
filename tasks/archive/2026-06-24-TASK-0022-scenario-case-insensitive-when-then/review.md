---
status: resolved
summary: "Case-insensitive WHEN/THEN + информативное сообщение валидатора; минимальный корректный diff, полный rspec зелёный."
verdict: accepted
ready: true
---

# Summary

Ревью изменения `WhenThenChecker`: ключевые слова WHEN/THEN распознаются
регистронезависимо (`/i`), сообщение об отсутствующей клаузе теперь показывает
ожидаемый формат строки. Изменение минимальное и точно соответствует brief/plan.

# Findings

- `CLAUSE_RES`: добавлен флаг `i` к обоим регэкспам; сохранена толерантность к
  префиксам `[\s>*-]*\**\s*` и обратная совместимость с UPPERCASE. Корректно.
- `violation.description`: переписан на информативный текст с примером формата
  `'- <KEYWORD> …'` и пометкой case-insensitive; ключи `type:
  'scenario_missing_clause'` и `missing: keyword` НЕ изменены — зависимые проверки
  (`brief_grammar_spec` по `missing`, `validation/api_spec` по `type`) не затронуты.
- Структурные проверки (наличие `#### Scenario:`, обеих клауз) сохранены — ослаблена
  только чувствительность к регистру, как и требовалось.
- Тесты: добавлены Title-case/lower-case/UPPERCASE кейсы + ассерт на формат сообщения.

# Resolution

Принято без изменений (verdict: accepted). Дефектов не выявлено.

# Remediation

Не требуется.

# Residual risks

- `SCENARIO_RE` (заголовок `Scenario`) остаётся регистрозависимым — осознанно вне
  scope: канон шаблонов фиксирует `#### Scenario:`. При будущем запросе можно
  применить ту же толерантность.

# Verification

- Полный `bundle exec rspec`: 1797 примеров, 0 падений, 1 pending (преэкзистинг).
- Таргетные спеки валидатора: 37 примеров, 0 падений.
- RuboCop на изменённых файлах: 0 offenses.
