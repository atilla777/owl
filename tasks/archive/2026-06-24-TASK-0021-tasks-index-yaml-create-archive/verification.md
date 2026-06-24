---
status: passed
summary: "Сериализация записи tasks/index.yaml под локом `index` реализована и покрыта тестами; полный rspec зелёный, RuboCop net-zero."
---

# Summary

Все писатели `tasks/index.yaml` (create / archive / delete / abandon / set-priority /
rebuild) переведены на единый locked-write путь `Owl::Tasks::Internal::IndexWriter`,
который захватывает repo-scoped лок `index`, выполняет scan+atomic-write и освобождает
лок в `ensure`. Проверки пройдены, регрессионные тесты на сериализацию добавлены.

# Commands

- `bundle exec rspec`
- `git checkout README.md` (известный test-isolation wart)
- `bundle exec rubocop <8 изменённых файлов>`
- grep-аудит: единственный вызывающий `IndexRebuilder.rebuild` теперь `IndexWriter`.

# Outcomes

- rspec: **1793 примера, 0 падений, 1 pending** (преэкзистинг SQLite-concurrency
  placeholder).
- Покрытие: все `lib/owl/**/api.rb` остаются на 100% в полном прогоне (api.rb не
  затрагивались).
- RuboCop: **0 offenses** на изменённых файлах (net-zero).
- Новый спек `index_writer_spec.rb`: 6 примеров — сериализация/таймаут,
  retry-success, release-on-exception (leaf), отсутствие self-deadlock в цепочке
  create→create→delete.

# Not run

- Реальный мультипроцессный стресс-тест параллельных оркестраторов (моделируется
  юнит-тестом сериализации; полноценный нагрузочный прогон — вне scope).
- Smoke в отдельном временном проекте (механика лока покрыта юнит-тестами).

# Failures or blockers

Нет. Все запланированные проверки зелёные.

# Residual risks

- Константы `IndexWriter` (дедлайн 10s, backoff 20ms) зашиты в коде; при экстремальной
  параллельной нагрузке исчерпание дедлайна вернёт восстановимый `lock_held` —
  корректный сигнал, но значения при необходимости можно вынести в конфиг.
- Лок покрывает FS-индекс; полный переход на транзакционный бэкенд (SQLite) — отдельная
  работа P3.
