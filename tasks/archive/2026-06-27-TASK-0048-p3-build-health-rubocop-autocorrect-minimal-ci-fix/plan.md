---
status: approved
summary: Пошаговый план build-health — точечный SimpleCov-гейт + unit-тест, зелёный RuboCop (autocorrect → ручной lib → spec-послабления), GitHub Actions CI, version-bump.
---

# Goal

Реализовать три цели брифа единым изменением: (1) SimpleCov-гейт срабатывает
только на полном прогоне suite и бесшумен на частичном; (2)
`bundle exec rubocop` выходит с кодом 0; (3) добавлен блокирующий GitHub
Actions workflow (полный `rspec` + `rubocop`). Реализация следует design.md
без повторного выбора подходов.

# Checklist

- [ ] **Coverage-гейт.** В `spec/spec_helper.rb` вынести детекцию полного
      прогона в приватный helper: `full_suite_run?` сравнивает
      `RSpec.configuration.files_to_run` (map `File.expand_path`, sort) с
      полным набором `Dir.glob('spec/**/*_spec.rb').map { File.expand_path }`
      (sort). В `SimpleCov.at_exit` добавить ранний `next unless full_suite_run?`
      перед проверкой недопокрытых API-файлов. Поведение на полном прогоне
      сохранить дословно (печать нарушителей + `exit 1`).
- [ ] **Тест гейта.** Добавить `spec/spec_helper_coverage_gate_spec.rb` (или
      эквивалент), который юнит-тестирует логику сравнения множеств: совпадение
      → полный прогон (true), подмножество → частичный (false). Тест не должен
      сам триггерить `exit`/`at_exit` — извлечь сравнение в тестируемый
      module-метод (напр. `Owl`-агностичный helper в support/), который зовёт и
      `at_exit`, и тест.
- [ ] **RuboCop safe autocorrect.** Прогнать `bundle exec rubocop -a` по всему
      репозиторию (≈39 нарушений: Semicolon, BlockDelimiters, LineLength,
      EmptyClassDefinition, Next, Argument/HashAlignment, IfUnlessModifier,
      MultipleComparison, RedundantException, UnusedMethodArgument в спеках,
      RedundantCopDisableDirective, HookArgument).
- [ ] **RuboCop unsafe autocorrect (точечно).** Где безопасно — применить
      `-A` для `Lint/AmbiguousRange` и `Style/SafeNavigation` в lib, проверив
      каждый дифф вручную; если правка меняет смысл — чинить руками.
- [ ] **lib/ ручные правки (по коду, не Exclude).** Устранить оставшиеся
      нарушения в 12 файлах lib/bin: `Metrics/CyclomaticComplexity`(3),
      `Metrics/PerceivedComplexity`(3), `Metrics/AbcSize`(1),
      `Metrics/ModuleLength`(1), `Metrics/ParameterLists`(1),
      `Naming/MethodParameterName`(2), `Lint/NoReturnInBeginEndBlocks`(1) —
      малыми безопасными рефакторингами (извлечение метода, ранний возврат,
      осмысленное имя параметра). Если конкретное нарушение нельзя устранить
      кодом без риска для поведения — остановиться и поднять вопрос, не глушить
      коп Exclude в lib.
- [ ] **spec/ послабления конфига.** В `.rubocop.yml` под `spec/**` ослабить
      spec-копы с комментарием-обоснованием: `RSpec/ExampleLength`,
      `RSpec/MultipleExpectations`, `RSpec/MultipleMemoizedHelpers`,
      `RSpec/InstanceVariable`, `RSpec/LeakyConstantDeclaration`,
      `RSpec/LeakyLocalVariable`, `RSpec/ContextWording`,
      `Lint/ConstantDefinitionInBlock`. Послабления только для `spec/**`.
- [ ] **.rubocop.yml — deprecation.** Заменить `require:` на `plugins:` для
      `rubocop-performance`/`rubocop-rspec`, чтобы убрать предупреждение о
      миграции (чистый вывод линтера).
- [ ] **CI workflow.** Создать `.github/workflows/ci.yml`: триггеры `push` и
      `pull_request`; `permissions: contents: read`; один job на
      `ubuntu-latest`; шаги `actions/checkout@v4` →
      `ruby/setup-ruby@v1` (`ruby-version: '3.3'`, `bundler-cache: true`) →
      `bundle exec rspec` → `bundle exec rubocop`.
- [ ] **Версия + CHANGELOG.** Так как менялся `lib/**/*.rb`, поднять
      `Owl::VERSION` на patch и добавить запись в `CHANGELOG.md` тем же
      изменением (back-compat, без смены поведения CLI/JSON).

# Smoke test

- `bundle exec rspec spec/owl/<любой-один>_spec.rb` → exit 0 (гейт молчит).
- `bundle exec rspec` → полный suite зелёный, гейт активен (при 100% API —
  exit 0; искусственно понизив покрытие — печатает нарушителя и exit 1).
- `bundle exec rubocop` → `no offenses detected`, exit 0, без deprecation-варнингов.

# Scope

`spec/spec_helper.rb` + новый spec гейта; `.rubocop.yml`; точечные правки
нарушений в `lib/` и `bin/`; `.github/workflows/ci.yml`; `lib/owl/version.rb`
(или где определён `Owl::VERSION`) + `CHANGELOG.md`.

# Constraints

- Послабления RuboCop — только для `spec/**`; в `lib/` нарушения чинятся кодом.
- Покрытие публичных API-файлов (`lib/owl/**/{api,result}.rb`) остаётся 100%.
- Рефакторинг lib — поведение-сохраняющий; никакого изменения CLI/JSON-контракта.
- Конституция §7.1: patch-бамп `Owl::VERSION` + CHANGELOG в том же коммите
  (триггер — правки lib).
- Доступ к состоянию Owl — только через `bin/owl` (правки тут его не трогают).

# Files to inspect

- `spec/spec_helper.rb` (гейт), `spec/support/` (helper для теста).
- `.rubocop.yml` (послабления + plugins).
- lib/bin с нарушениями: `lib/owl/cli/internal/commands/{config_set,task_list,workflow_diagram_data}.rb`,
  `lib/owl/config/internal/{path_accessor,serializer,validator}.rb`,
  `lib/owl/publish/internal/publisher.rb`,
  `lib/owl/steps/internal/drift_detector.rb`,
  `lib/owl/subagents/api.rb`, `lib/owl/subagents/internal/output_spec.rb`,
  `lib/owl/validation/internal/schema_resolver.rb`,
  `lib/owl/workflows/internal/workflow_validator.rb`.
- `lib/owl/version.rb`, `CHANGELOG.md`.
- `owl-cli.gemspec` (сверить требуемую версию Ruby для CI).

# Tests and verification

- Новый unit-тест на детектор полного прогона (true/false по множествам файлов).
- Полный `bundle exec rspec` зелёный, гейт сохраняет строгость на полном прогоне.
- Частичный `rspec <один файл>` → exit 0.
- `bundle exec rubocop` → 0 нарушений, exit 0.
- Покрытие `api.rb`/`result.rb` остаётся 100% (полный прогон не печатает
  нарушителей).

# Out of scope

- SQLite-бэкенд, новые workflow/artifact-определения.
- Рефакторинг продакшен-логики сверх минимума для устранения RuboCop-нарушений.
- Матричный CI, отдельные jobs, кэш-стратегии сверх `bundler-cache: true`.
- Любые изменения CLI-поверхности или JSON-контрактов.
