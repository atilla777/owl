# Owl Ruby code architecture

Extends [[owl-project-constitution]] §5.10.
Sibling rule: [[owl-ruby-service-objects-and-oop]].

---

# Owl Ruby code architecture

## 1. Назначение

Правило фиксирует доменно-ориентированную организацию Ruby-кода Owl CLI: какие
домены признаются, как именуются namespaces, какой публичный фасад каждый
домен предоставляет, как устроен layout файлов, и как оформляются возвраты
публичного API. Это не каноническая DDD-методология (без aggregates / domain
events / repositories в обязательной форме), а **modular, domain-oriented
architecture** — discipline границ доменов.

## 2. Перечень доменов

Границы доменов зафиксированы и не торгуются на ходу. Если работа требует
нового домена — это отдельное решение, оформляется обновлением этого правила.

- `Owl::Config` — чтение/валидация `.owl/config.yaml` и реестров (`workflows.yaml`,
  `artifacts.yaml`).
- `Owl::Workflows` — реестр и схемы workflow, граф шагов и артефактов.
- `Owl::Artifacts` — реестр типов артефактов, шаблоны, JSON Schema валидация.
- `Owl::Tasks` — task state, index, parent/child, текущая задача.
- `Owl::Storage` — storage resolver (логические роли → физические пути),
  адаптеры файлового backend.
- `Owl::Steps` — Step invocations, ready/blocked steps.
- `Owl::Validation` — structural / semantic валидация артефактов.
- `Owl::Cli` — тонкий entry-point: парсинг аргументов, JSON-вывод, exit codes.

## 3. Namespace и фасад

Каждый домен предоставляет **ровно один** публичный фасад:

```
Owl::<Domain>::Api
```

Это единственная поверхность, на которую опираются другие домены и CLI.
Никакой внешний код не должен импортировать классы из `Owl::<Domain>::Internal::*`
напрямую.

Внутренние реализации — под `Owl::<Domain>::Internal::*`. Ruby не enforce-ит
приватность модулей; конвенция поддерживается ревью и линтером (например,
кастомный RuboCop cop в перспективе).

Пример:

```ruby
module Owl
  module Tasks
    module Api
      def self.create_task(params)
        Internal::CreateTask.call(params)
      end

      def self.find_current
        Internal::FindCurrent.call
      end
    end

    module Internal
      class CreateTask
        # ...
      end

      class FindCurrent
        # ...
      end
    end
  end
end
```

## 4. CLI как тонкий адаптер

`Owl::Cli::*` отвечает только за:

- парсинг аргументов командной строки (Thor / OptionParser);
- конвертацию входных строк в типизированные параметры;
- вызов соответствующего метода `Owl::<Domain>::Api`;
- сериализацию результата (JSON, человеческий вывод);
- exit codes (`0` на `Owl::Result::Ok`, ненулевые — на `Owl::Result::Err`).

В `Owl::Cli::*` запрещены:

- бизнес-логика;
- чтение/запись файлов напрямую (только через `Owl::Storage::Api`);
- знание о форме `.owl/`, `tasks/`, `docs/` (это знание лежит в `Owl::Storage`).

## 5. Return-контракт публичного API

Все методы фасада `Owl::<Domain>::Api` возвращают значение типа `Owl::Result`:

```ruby
module Owl
  module Result
    Ok  = Data.define(:value)
    Err = Data.define(:code, :message, :details)
  end
end
```

- `Owl::Result::Ok.new(value:)` — успех; `value` — `Data.define`-структура
  домена или примитив.
- `Owl::Result::Err.new(code:, message:, details:)` — ошибка; `code` —
  `Symbol` из перечня кодов домена (`Owl::Tasks::ErrorCodes` или эквивалент),
  `message` — человеко-читаемая строка, `details` — `Hash` с диагностикой.

Внутри домена сервисы могут оперировать обычными значениями и исключениями;
конвертация в `Owl::Result` происходит на уровне фасада.

Использование `dry-monads` или сторонних Result-библиотек **запрещено**
(см. правило зависимостей в [[owl-ruby-service-objects-and-oop]]).

## 6. File / folder layout

```
lib/
  owl/
    result.rb                       # Owl::Result::Ok / Err
    config/
      api.rb                        # Owl::Config::Api
      internal/
        load_config.rb
        ...
    workflows/
      api.rb
      internal/
        ...
    tasks/
      api.rb
      error_codes.rb                # Owl::Tasks::ErrorCodes
      internal/
        create_task.rb
        find_current.rb
        ...
    storage/
      api.rb
      internal/
        filesystem.rb               # файловый адаптер
    cli/
      runner.rb                     # bin/owl entry
      commands/
        task.rb
        step.rb
        ...
bin/
  owl                               # exec'ит Owl::Cli::Runner
spec/
  spec_helper.rb
  owl/
    result_spec.rb
    tasks/
      api_spec.rb
      internal/
        create_task_spec.rb
```

Тестовый каталог — `spec/`. Owl — не Rails, поэтому предупреждение
Constitution §5.2 про конфликт `spec/` с RSpec не применимо. Test framework —
RSpec; правила юнит-тестов и покрытия публичного API см.
[[owl-ruby-testing-and-public-api-coverage]].

## 7. Запрещено

- Прямой `require`/вызов классов из `Owl::<Domain>::Internal::*` за пределами
  своего домена.
- Бизнес-логика в `Owl::Cli::*` или в Thor-командах.
- File / ENV / exec / HTTP I/O в фасаде или в `Owl::Cli` — только через
  адаптеры из `Owl::Storage` либо аналогичных явных слоёв.
- Глобальные singleton'ы. Единственное исключение — `Owl::Config.current`
  как явно обсуждаемая конструкция конфига.

## 8. Тестирование

- Test framework — RSpec; layout, конфиг SimpleCov, правила 100% покрытия
  публичного API — см. [[owl-ruby-testing-and-public-api-coverage]].
- Юнит-тесты домена бьют по фасаду `Owl::<Domain>::Api` (поведенческие)
  либо по конкретному `Internal::*` сервису (изоляция логики).
- Cross-domain зависимости мокаются **только** на уровне фасадов
  (`Owl::Storage::Api`, `Owl::Tasks::Api`, …). Никаких моков на
  `Owl::Tasks::Internal::*` из тестов другого домена.

## 9. Эволюция правила

- Добавление нового домена — обновление §2 и архитектурного дерева в §6.
- Изменение формы возврата (`Owl::Result`) — обновление §5 + §5.10 конституции.
- Допущение исключений из правила «фасад единственный»
  (например, internal-pub/sub) оформляется как поправка к этой статье,
  а не локальное решение в PR.

