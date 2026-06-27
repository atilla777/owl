---
status: approved
summary: Привести build-health репозитория Owl в порядок — точечный SimpleCov-гейт (без exit 1 на частичных прогонах), полностью зелёный RuboCop и минимальный блокирующий CI на GitHub Actions (rspec + rubocop).
---

# Problem

Здоровье сборки репозитория Owl деградировало по трём независимым осям:

1. **SimpleCov-гейт даёт `exit 1` на частичных прогонах.** Хук
   `SimpleCov.at_exit` в `spec/spec_helper.rb:17-32` проверяет, что каждый
   `lib/owl/**/api.rb` и `result.rb` покрыт на 100% строк, и при недоборе
   зовёт `exit 1`. На частичном прогоне (`rspec spec/owl/foo_spec.rb`)
   загружается лишь часть API-файлов, поэтому гейт видит <100% и валит
   процесс — красный выход при нуле упавших тестов. Это ломает локальную
   разработку (нельзя гонять подмножество спеков) и любую IDE/watch-итерацию.

2. **RuboCop не зелёный.** `bundle exec rubocop` находит 77 нарушений в 519
   файлах (39 автокорректируемых, ~38 — нет). Среди некорректируемых:
   `Layout/LineLength`, метрики сложности (`Metrics/Cyclomatic`/`Perceived`),
   spec-копы (`RSpec/LeakyLocalVariable`, `RSpec/LeakyConstantDeclaration`,
   `RSpec/ExampleLength`), `Lint/UnusedMethodArgument`,
   `Lint/ConstantDefinitionInBlock`. Нет чистого стилевого базиса, на который
   можно опереть линт-гейт.

3. **Нет CI.** В репозитории отсутствуют `.github/workflows/` и
   `.gitlab-ci.yml`. Remote — GitHub (`atilla777/owl`). Регрессии в тестах
   или стиле ловятся только вручную локально; нет автоматического барьера на
   push/PR.

# Goal

Сделать сборку Owl предсказуемо зелёной и защищённой автоматикой:

- SimpleCov-гейт строгий ровно на полном прогоне и полностью бесшумен на
  частичном — `exit 1` отражает только результат тестов, кроме случая полного
  прогона с реальным недобором покрытия публичного API.
- `bundle exec rubocop` выходит с кодом 0 (0 нарушений) за счёт безопасного
  autocorrect, точечной ручной правки нарушений в `lib/` и обоснованного
  послабления конфигурации для spec-копов.
- Минимальный GitHub Actions workflow на push и pull_request прогоняет полный
  rspec (с активным coverage-гейтом) и rubocop, оба — блокирующие.

Не в зоне: SQLite-бэкенд, новые рабочие процессы, рефакторинг продакшен-логики
сверх того, что требуется для устранения нарушений RuboCop.

# Scenarios

### Requirement: Coverage gate scoped to the full suite

The system SHALL invoke the public-API 100% line-coverage gate only when
RSpec is executing the complete spec suite, and SHALL NOT exit non-zero from
the gate on any partial run.

#### Scenario: Partial run does not trip the gate
- WHEN разработчик запускает подмножество спеков (`rspec spec/owl/foo_spec.rb`)
- THEN хук `at_exit` НЕ вызывает `exit 1` из-за недобора покрытия API
- AND код выхода процесса определяется только результатом самих тестов

#### Scenario: Full run still enforces 100% API coverage
- WHEN RSpec прогоняет полный suite и хотя бы один `api.rb`/`result.rb`
  покрыт < 100% строк
- THEN гейт печатает список недопокрытых файлов с процентами
- AND процесс завершается с `exit 1`

#### Scenario: Clean full run exits zero
- WHEN RSpec прогоняет полный suite и все `api.rb`/`result.rb` покрыты на 100%
- THEN гейт не печатает предупреждений и не меняет код выхода
- AND процесс завершается с кодом 0

### Requirement: RuboCop is clean

The system SHALL produce zero offenses on `bundle exec rubocop`.

#### Scenario: Lint passes with no offenses
- WHEN запускается `bundle exec rubocop` по всему репозиторию
- THEN вывод сообщает «no offenses detected»
- AND код выхода равен 0

### Requirement: CI runs rspec and rubocop as blocking gates

The system SHALL run the full RSpec suite and RuboCop on every push and pull
request via GitHub Actions, and SHALL fail the workflow if either step fails.

#### Scenario: Green change passes CI
- WHEN коммит запушен или открыт PR, а тесты и линт зелёные
- THEN workflow выполняет `bundle install`, полный `rspec` (с активным
  coverage-гейтом) и `rubocop`
- AND статус workflow — success

#### Scenario: Failing tests block the build
- WHEN в PR падает хотя бы один rspec-пример
- THEN job с rspec завершается с ненулевым кодом
- AND статус workflow — failure

#### Scenario: Lint offense blocks the build
- WHEN изменение вносит нарушение RuboCop
- THEN job с rubocop завершается с ненулевым кодом
- AND статус workflow — failure

# Edge cases

- **Прогон одного файла.** `config.files_to_run.one?` (одиночный файл) — это
  частный случай частичного прогона: гейт обязан молчать. Детектор «полного
  прогона» не должен путать single-file run с полным suite.
- **Определение «полного прогона».** Критерий — `files_to_run` равен полному
  набору спеков проекта (а не наличие аргументов в командной строке: `rspec`
  без аргументов и `rspec spec` оба обязаны считаться полным прогоном). Тег- и
  example-фильтры (`-e`, `--tag`) на полном наборе файлов — пограничный случай;
  допустимо считать их полным прогоном (гейт активен), главное — частичный
  набор файлов гейт не активирует.
- **Послабления RuboCop должны быть обоснованы.** Конфиг-послабления — только
  для spec-копов, где это оправдано тестовым стилем; не глушить копы в `lib/`
  ради зелёного цвета. Нарушения в `lib/` чинятся кодом, а не `Exclude`.
- **Покрытие публичного API не должно падать.** Ручная правка `api.rb`/
  `result.rb` под RuboCop обязана сохранить 100% покрытие — иначе полный прогон
  и CI станут красными (это и есть назначение гейта).
- **Версия Ruby в CI.** Workflow обязан использовать Ruby, совместимый с
  `TargetRubyVersion: 3.3` и гемспеком; кэш бандла — по желанию, но без него
  job обязан проходить.
- **Версионирование (Конституция §7.1).** `spec/**` и CI-файлы не требуют
  бампа `Owl::VERSION`. Но если ради зелёного RuboCop правится любой
  `lib/**/*.rb`, требуется patch-бамп `Owl::VERSION` + запись в `CHANGELOG.md`
  тем же коммитом (back-compat рефактор без смены поведения).

# Acceptance criteria

- [ ] `rspec spec/owl/<любой-один>_spec.rb` завершается кодом 0 при зелёных
      тестах (гейт не вмешивается на частичном прогоне).
- [ ] Полный `rspec` сохраняет строгий гейт: при недоборе покрытия публичного
      API печатает нарушителей и выходит с `exit 1`; при 100% — выходит 0.
- [ ] `bundle exec rubocop` сообщает 0 нарушений и выходит с кодом 0.
- [ ] Послабления `.rubocop.yml` ограничены spec-копами и снабжены коротким
      обоснованием в комментарии; нарушения в `lib/` устранены кодом.
- [ ] Добавлен `.github/workflows/ci.yml` (GitHub Actions), который на push и
      pull_request прогоняет полный `rspec` и `rubocop`; оба шага блокирующие.
- [ ] Покрытие публичных API-файлов остаётся 100% после правок.
- [ ] Если менялся любой `lib/**/*.rb` — бамп `Owl::VERSION` (patch) и запись в
      `CHANGELOG.md` в том же коммите; иначе бамп не требуется.
