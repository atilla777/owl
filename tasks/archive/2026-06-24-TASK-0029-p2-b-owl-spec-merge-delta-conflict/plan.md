# Goal

Сделать `DeltaMerger.apply` идемпотентным: повторное применение применённого delta —
no-op, genuine-конфликт (то же имя, другое содержимое) — по-прежнему `delta_conflict`.

# Scope

- `lib/owl/specs/internal/delta_merger.rb`: `add` (idempotent/conflict), `remove`
  (idempotent для отсутствующей цели).
- Честные счётчики no-op в summary (merge_engine), если дёшево.
- Тесты + bump `Owl::VERSION` (patch) + CHANGELOG.

# Constraints

- Genuine-конфликт = имя совпадает И нормализованное содержимое РАЗЛИЧАЕТСЯ → только
  тогда `delta_conflict`.
- Идентичность сравнивать по нормализованному блоку (`normalize` уже приводит body к
  единому виду; сравнивать `requirements[index] == normalize(block)`).
- `modify` уже идемпотентен (повторная установка того же содержимого = no-op) — не
  ломать; `MODIFY` отсутствующей цели остаётся `delta_target_missing` (genuine).
- Не менять формат delta/спека и семантику операций кроме идемпотентности.
- 100% покрытие затронутых `**/api.rb` (specs/api.rb если затронут); patch bump.

# Checklist

1. **`add`.** Для каждого блока: `index = index_of(...)`.
   - нет индекса → добавить `normalize(block)` (как сейчас);
   - есть индекс И `requirements[index] == normalize(block)` → **no-op** (already
     applied), не ошибка;
   - есть индекс И содержимое отличается → `conflict(name)` (genuine).
2. **`remove`.** Для каждого имени: `index = index_of(...)`.
   - нет индекса → **no-op** (already removed), не `target_missing`;
   - есть → удалить (как сейчас).
3. **`modify`.** Оставить как есть (идемпотентен); подтвердить тестом, что повторный
   MODIFY к тому же содержимому — no-op; `MODIFY` отсутствующей цели — `target_missing`.
4. **Честные счётчики (если дёшево).** Прокинуть из `apply`/`add`/`remove` число
   no-op'ов (unchanged/already-applied), чтобы `merge_engine.summarize`/`counts`
   отражали их отдельно от реально применённых. Если это требует широкой переделки —
   минимально: не считать no-op как applied (или явный `unchanged` счётчик). Решение
   зафиксировать в отчёте.
5. **Тесты:** idempotent ADDED (тот же контент → no-op); genuine ADDED conflict (другой
   контент → delta_conflict); idempotent REMOVE (отсутствует → no-op); MODIFY к тому же
   → no-op; MODIFY отсутствующей цели → target_missing; **двойной полный
   `owl spec merge`** одного delta идемпотентен (второй успешен, спек стабилен). Покрыть
   изменённые ветки.
6. Bump `Owl::VERSION` (patch) + `CHANGELOG.md`.

# Files to inspect

- `lib/owl/specs/internal/delta_merger.rb` — `add`/`remove`/`modify`/`normalize`.
- `lib/owl/specs/internal/merge_engine.rb` — `apply`/`summarize`/`counts` (честные
  счётчики).
- `lib/owl/specs/api.rb` — публичный `merge` (контракт; покрытие если затронут).
- `spec/owl/specs/**` — существующие тесты merger/merge (найти и расширить).
- `lib/owl/version.rb`, `CHANGELOG.md`.

# Tests and verification

- Юнит на delta_merger: все сценарии checklist 5.
- Интеграционный: `owl spec merge` дважды подряд на одном delta → второй ok, спек
  идентичен.
- `bundle exec rspec` зелёный (после — `git checkout README.md`).
- 100% покрытие затронутых `**/api.rb`; RuboCop net-zero.

# Smoke test

```
# применить delta:
owl spec merge <domain> --json        # ok, applied
# повторно тот же delta:
owl spec merge <domain> --json        # ok (no-op/unchanged), НЕ delta_conflict
# delta с ADDED того же имени, но другим телом:
owl spec merge <domain> --json        # delta_conflict (genuine)
```

# Out of scope

- Изменение формата/семантики delta кроме идемпотентности. Условные шаги (TASK-0028).
