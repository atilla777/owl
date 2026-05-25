# Owl Ruby service objects and OOP

Extends [[owl-project-constitution]] §5.10.
Sibling rule: [[owl-ruby-code-architecture]].

---

# Owl Ruby service objects and OOP

## 1. Назначение

Правило фиксирует форму классов, в которых живёт бизнес-логика Owl, и набор
OOP-принципов, которым обязаны следовать эти классы. Дополняет
[[owl-ruby-code-architecture]] (где про границы доменов, фасад и layout)
и §5.10 конституции.

## 2. Форма сервиса — single-action callable

Каждый сервис делает **одно действие**. Сервис живёт под
`Owl::<Domain>::Internal::*` и предоставляет `.call(...)`.

```ruby
module Owl
  module Tasks
    module Internal
      class CreateTask
        def self.call(params) = new(params).call

        def initialize(params, repository: Repository.new, clock: Time)
          @params     = params
          @repository = repository
          @clock      = clock
        end

        def call
          validate!
          task = build_task
          @repository.persist(task)
          task
        end

        private

        attr_reader :params, :repository, :clock

        def validate!
          # ...
        end

        def build_task
          # ...
        end
      end
    end
  end
end
```

Имя сервиса — глагол в Single-Action форме (`CreateTask`, `FindCurrent`,
`RebuildIndex`, `ResolvePath`). Никаких `TaskManager`, `TasksService` с
десятком методов внутри домена.

Aggregator-service (один класс с N публичных методов) допустим **только**
как реализация фасада `Owl::<Domain>::Api`, и сам фасад делегирует на
single-action сервисы — не пишет логику.

## 3. SRP — что не кладём в сервис

Сервис делает бизнес-операцию домена и **не** делает следующее:

- I/O: чтение/запись файлов, ENV, exec subshell, HTTP, чтение `stdin` —
  через адаптеры, инжектируемые в конструктор.
- Парсинг CLI-аргументов — это работа `Owl::Cli::*`.
- Сериализация артефактов в Markdown / YAML / JSON — `Owl::Artifacts`.
- Кросс-доменные операции — через вызов соседнего `Owl::<OtherDomain>::Api`,
  тоже инжектированного в конструктор.

Если сервис разрастается до >150 строк или >2 уровней вложенности — это
сигнал разнести на несколько single-action сервисов.

## 4. OOP-принципы

### 4.1. Constructor DI

Все зависимости — параметры конструктора со значениями по умолчанию.
Глобальные ссылки, синглтоны, `Kernel`-уровневые хелперы запрещены
(см. §7 [[owl-ruby-code-architecture]]).

```ruby
def initialize(params, repository: Owl::Tasks::Internal::Repository.new, clock: Time)
  # ...
end
```

### 4.2. Composition over inheritance

Наследование допускается только в редких типизированных иерархиях
(например, общая база для исключений домена). По умолчанию — модули и
композиция.

### 4.3. Tell, don't ask

Сервис исполняет операцию и возвращает результат. Не возвращает наружу
внутреннее состояние и не предоставляет «getter»-цепочки.

### 4.4. Immutable value objects

Входы и выходы публичной поверхности домена — `Data.define`-структуры
(Ruby 3.2+). Внутри домена допустим `Struct.new(..., keyword_init: true)`
как переходная форма, но `Data.define` предпочтительнее.

```ruby
module Owl
  module Tasks
    Task = Data.define(:id, :title, :workflow_id, :parent_id, :status, :created_at)
  end
end
```

Никаких mutable `Hash` в публичной поверхности фасада.

## 5. Возвраты и ошибки

- Внутри сервиса — обычные значения и **типизированные** исключения
  (`Owl::Tasks::Errors::Invalid`, `NotFound`, и т.п.). Исключения объявляются
  в домене (например, `lib/owl/tasks/errors.rb`).
- Конвертация в `Owl::Result::Ok` / `Owl::Result::Err` — на фасаде
  `Owl::<Domain>::Api`, не в сервисе. См. §5
  [[owl-ruby-code-architecture]].

## 6. Зависимости

Только stdlib. Запрещены без обновления этого правила:

- `dry-rb` (dry-monads, dry-struct, dry-validation, …);
- `interactor`;
- `trailblazer`;
- любая dependency-injection библиотека (dry-auto_inject, dry-system).

Причина — Owl персональный CLI с приоритетом на быстрый запуск, минимум
бутстрапа и читабельность кода. Внешние DSL осложняют отладку и поднимают
cold-start. Если конкретная задача требует исключения — оно оформляется
поправкой к этой статье через `update_knowledge_entry`.

## 7. Тесты

- Test framework — RSpec; layout, конфиг SimpleCov, правила 100% покрытия
  публичных методов — см. [[owl-ruby-testing-and-public-api-coverage]].
- Каждый single-action сервис тестируется напрямую: `described_class.call(...)`
  с подменёнными зависимостями через RSpec doubles.
- Тест проверяет один основной сценарий + одну ошибку (граничный SRP-щуп:
  если для покрытия одного сервиса нужно >5 сценариев — он делает слишком много).
- Кросс-доменные зависимости мокаются на уровне фасадов (`Owl::Storage::Api`),
  не на уровне внутренних классов соседнего домена.

## 8. Эволюция правила

- Любое исключение из §6 (например, ввод `dry-struct` ради контракта) —
  через апдейт этой статьи с обоснованием.
- Изменение формы сервиса (например, переход на класс с состоянием вместо
  callable) — апдейт §2 + согласование с фасадным контрактом из
  [[owl-ruby-code-architecture]].

