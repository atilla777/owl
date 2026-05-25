# Owl Ruby testing (RSpec) and public API coverage

Extends [[owl-project-constitution]] §5.10.
Sibling rules: [[owl-ruby-code-architecture]], [[owl-ruby-service-objects-and-oop]],
[[owl-ruby-linting-rubocop]].

---

# Owl Ruby testing (RSpec) and public API coverage

## 1. Назначение

Зафиксировать RSpec как обязательный test framework Owl и правило 100%
покрытия публичных методов (`Owl::<Domain>::Api`, `Owl::Result`) юнит-тестами.
Внутренние сервисы (`Internal::*`) тоже тестируются, но без жёсткого порога.

## 2. Почему RSpec, а не Minitest

Owl — не Rails. Constitution §5.2 предупреждает про конфликт `spec/` с RSpec
в корне Rails-проекта; в Owl этого конфликта нет, так что используем
идиоматический RSpec.

## 3. Конфигурация в репозитории

- `Gemfile` (`:development, :test`):
  - `rspec ~> 3.13`
  - `rubocop-rspec`
  - `simplecov`
- `.rspec`:
  ```
  --require spec_helper
  --format documentation
  --color
  ```
- `spec/spec_helper.rb`:
  - запускает `SimpleCov.start` с `enable_coverage :branch`, фильтром `/spec/`
    и группами `Public API` / `Result` / `Internal`;
  - в `SimpleCov.at_exit` проверяет, что **каждый** файл, попавший под
    `lib/owl/(.+/)?(api|result)\.rb`, имеет `covered_percent >= 100`;
    иначе печатает список нарушителей и выходит с кодом `1`.

## 4. Структура spec/

```
spec/
  spec_helper.rb
  owl/
    result_spec.rb
    tasks/
      api_spec.rb                  # покрывает все публичные методы фасада
      internal/
        create_task_spec.rb        # тесты внутренних сервисов (по желанию)
    storage/
      api_spec.rb
```

## 5. Что считается «покрытием публичного метода»

- **Минимум**: каждый публичный метод фасада (`Owl::<Domain>::Api.<method>`)
  имеет хотя бы один `describe '.<method>'` блок с **полным line coverage**
  тела метода и всех явных веток (`if`, `case`, ранний `return`).
  SimpleCov `enable_coverage :branch` помогает поймать пропущенные ветки.
- **Сценарии**: для каждого `Owl::Result::Err.code`, который метод может
  вернуть, должен быть тест, проверяющий именно этот код.

## 6. Когда запускать

- **После `implement`**: `bundle exec rspec`. Падение тестов или
  SimpleCov 100%-порога = фаза `implement` не закрыта.
- **На `verify`**: `bundle exec rspec` входит в обязательный набор.
  Аналогично — падение SimpleCov-проверки публичного API ломает verify.
- **На `review`**: ревьюер проверяет, что у каждого нового публичного
  метода фасада есть `describe`-блок и что coverage-отчёт не сообщает
  о проблемах.

## 7. Что НЕ enforce-ится этим правилом

- 100% line coverage всего `lib/owl/**` — нет; только публичные файлы.
- 100% mutation coverage — нет (не используем mutation testing в MVP).
- Тесты на `Owl::Cli::*` — минимально, проверяют только парсинг
  и делегирование на `Owl::<Domain>::Api`; основная логика тестируется
  на фасадах.

## 8. Лимиты и исключения

- Если файл фасада не имеет исполняемых строк (например, чистый
  `module … end` с делегациями через `Forwardable`) — SimpleCov всё равно
  отметит его 100%, специальных правил не нужно.
- Временные исключения (новый файл, фасад в процессе разработки) —
  **запрещены через `# :nocov:`** в коде. Если фасад нельзя покрыть на
  100% — это значит, что фасад выпускается без тестов; ловится на verify.

## 9. Стоп-условия

- `rspec` падает с инфраструктурной ошибкой (loaderror, network) —
  остановиться, не глушить тест.
- SimpleCov сообщает <100% для `api.rb` — не отключать SimpleCov-чек
  и не понижать порог; дописать тест на непокрытую ветку.
- Хочется ослабить правило (например, 95% вместо 100%) — обновить эту
  статью через `update_knowledge_entry`, не править `spec_helper.rb`
  молча.

