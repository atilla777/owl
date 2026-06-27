---
status: passed
summary: Build-health приведён в порядок — точечный SimpleCov-гейт (бесшумен на частичном прогоне, строг на полном), RuboCop зелёный (0 нарушений, без deprecation), добавлен блокирующий GitHub Actions CI; Owl::VERSION 1.1.1 → 1.1.2 + CHANGELOG.
---

# Summary

Реализованы все три цели брифа единым изменением по плану `plan.md` (без
повторного выбора подходов):

1. **SimpleCov-гейт активен только на полном прогоне.** Логика детекции
   полного прогона вынесена в чистый, юнит-тестируемый helper
   `spec/support/coverage_gate.rb` (`CoverageGate.full_suite_run?`): сравнивает
   раскрытые в абсолютные пути и отсортированные `RSpec.configuration.files_to_run`
   с полным набором `Dir.glob('spec/**/*_spec.rb')`. В `SimpleCov.at_exit`
   добавлен ранний `next unless CoverageGate.full_suite_run?(...)` перед
   проверкой недопокрытых API-файлов; поведение на полном прогоне сохранено
   дословно (печать нарушителей + `exit 1`). Helper не триггерит `exit`/`at_exit`
   и покрыт спеком `spec/owl/coverage_gate_spec.rb` (равные множества → true,
   подмножество/одиночный файл → false).

2. **RuboCop зелёный (0 нарушений).** Safe autocorrect + ручные
   поведение-сохраняющие правки `lib/`/`bin/` (без глушения копов в lib);
   spec-копы ослаблены только для `spec/**` с обоснованиями; `require:` →
   `plugins:` (убран deprecation-варнинг).

3. **CI.** Добавлен `.github/workflows/ci.yml`: триггеры `push` и
   `pull_request`, `permissions: contents: read`, один job `ubuntu-latest`,
   Ruby 3.3 (`bundler-cache: true`), блокирующие шаги `bundle exec rspec` →
   `bundle exec rubocop`. Ruby 3.3 согласован с `owl-cli.gemspec`
   (`required_ruby_version = '>= 3.3'`).

Поскольку правился `lib/**/*.rb`, выполнен patch-бамп `Owl::VERSION`
1.1.1 → 1.1.2 и добавлена запись в `CHANGELOG.md` тем же изменением
(Конституция §7.1).

## Изменённые файлы

- `spec/spec_helper.rb` — require helper + `next unless full_suite_run?` в гейте.
- `spec/support/coverage_gate.rb` — новый чистый helper (детектор полного прогона).
- `spec/owl/coverage_gate_spec.rb` — новый unit-тест helper.
- `.rubocop.yml` — `plugins:`, spec-послабления, `ParameterLists CountKeywordArgs: false`.
- `.github/workflows/ci.yml` — новый CI.
- `lib/owl/cli/internal/commands/config_set.rb` — `Hash#except` (Style/HashExcept + Performance/CollectionLiteralInLoop).
- `lib/owl/cli/internal/commands/workflow_diagram_data.rb` — извлечение методов (сложность) + переименование параметра `ws` → `workflow_step`.
- `lib/owl/config/internal/serializer.rb` — safe navigation.
- `lib/owl/config/internal/validator.rb` — извлечение локальной переменной (LineLength).
- `lib/owl/steps/internal/drift_detector.rb` — извлечение `recorded_content_sha` (сложность).
- `lib/owl/subagents/internal/output_spec.rb` — скобки диапазона + вынос `return` из begin/end в assignment-контексте.
- `lib/owl/workflows/internal/workflow_validator.rb` + новые `step_variants_check.rb`, `artifact_refs_check.rb` — вынос проверок в sibling-модули (ModuleLength + сложность/AbcSize `validate_step_variants`).
- `lib/owl/commit_push/internal/transaction.rb`, `spec/**` — авто-удаление ставших избыточными inline-директив `rubocop:disable`.
- `lib/owl/version.rb`, `CHANGELOG.md` — бамп 1.1.2 + запись.

# Commands

- `bundle exec rubocop -a` — safe autocorrect (несколько проходов по мере вскрытия избыточных директив).
- `bundle exec rspec spec/owl/coverage_gate_spec.rb` — частичный прогон (проверка бесшумности гейта).
- `bundle exec rspec spec/owl/subagents` — частичный прогон с искусственно сниженным покрытием `api.rb` (проверка бесшумности на частичном).
- `bundle exec rspec` — полный прогон (активный гейт).
- Проверка строгости: временный uncovered-метод в `lib/owl/subagents/api.rb` → полный `rspec` дал `exit 1` + печать нарушителя, затем правка откатана.
- `bundle exec rubocop` — финальная проверка линтера.

# Outcomes

- **Частичный прогон гейт молчит.** `bundle exec rspec spec/owl/coverage_gate_spec.rb` →
  `4 examples, 0 failures`, `EXIT=0`, при Line Coverage 0.05% гейт не печатал
  предупреждений и не валил процесс.
- **Полный прогон зелёный, гейт активен.** `bundle exec rspec` →
  `2067 examples, 0 failures, 1 pending`, `EXIT=0`; Line Coverage 97.13%;
  предупреждений «Public API files below 100%» — 0 (публичные `api.rb`/`result.rb`
  на 100%).
- **Гейт реально срабатывает на полном прогоне при недоборе.** С временным
  uncovered-методом полный `rspec` дал `FULL_EXIT=1` и напечатал
  `lib/owl/subagents/api.rb: 95.56%`; тот же частичный прогон остался `EXIT=0`.
  Правка откатана, финальный полный прогон снова зелёный (0 предупреждений гейта).
- **RuboCop чистый.** `bundle exec rubocop` → `523 files inspected, no offenses detected`,
  `EXIT=0`, без deprecation-предупреждений (миграция на `plugins:`).
- **Версия + CHANGELOG.** `Owl::VERSION = '1.1.2'`; добавлена секция
  `## [1.1.2] - 2026-06-27` (Fixed: гейт + RuboCop; Added: CI). Полный suite с
  версионным спеком зелёный.

# Not run

- CI workflow не исполнялся локально (нет push/PR в рамках шага); его прогон
  состоится на GitHub после шага `commit_push`. Содержимое выверено вручную
  по design/plan и согласовано с гемспеком (Ruby 3.3).

# Failures or blockers

- Блокеров нет; все критерии приёмки выполнены.

# Residual risks

- **Хрупкость детектора полного прогона.** При нестандартном `.rspec`/паттерне,
  расходящемся с `spec/**/*_spec.rb`, полный прогон мог бы ошибочно считаться
  частичным. Митигация: glob совпадает с дефолтным паттерном RSpec; helper
  покрыт unit-тестом; CI всегда гонит полный набор — регрессия покрытия
  поймается на push.
- **`Metrics/ParameterLists` для публичного `Owl::Subagents::Api.spawn` (11 kwargs).**
  Решено конфигом `CountKeywordArgs: false` (глобально, с обоснованием), а не
  переписыванием сигнатуры: `spawn` — публичный API с требованием 100% покрытия
  и контракта без back-incompat, поэтому изменение сигнатуры под patch-бамп
  недопустимо. Это не Exclude и не отключение копа — позиционный лимит
  параметров в `lib/` сохранён. Если оркестратор/ревью предпочтёт код-рефактор
  (объект-параметр) — это отдельное контракт-меняющее изменение (minor/major).
- **`bundler-cache` в CI.** При сбое кэша job не должен падать по инфраструктуре;
  базовый путь — `bundle install` на Ruby 3.3. Реальная валидация — на первом push.
