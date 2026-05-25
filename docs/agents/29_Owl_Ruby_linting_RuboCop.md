# Owl Ruby linting (RuboCop)

Extends [[owl-project-constitution]] §5.10.
Sibling rules: [[owl-ruby-code-architecture]], [[owl-ruby-service-objects-and-oop]].

---

# Owl Ruby linting (RuboCop)

## 1. Назначение

Зафиксировать RuboCop как обязательный линтер Owl и порядок его запуска
в KOS workflow. Правило обязательно подгружается на стадиях `implement`,
`verify`, `review` (см. `required_stages` этой статьи).

## 2. Конфигурация в репозитории

В корне Owl лежат:

- `.ruby-version` — `3.3.4` (минимум 3.2 из-за `Data.define` — см. §4.4
  [[owl-ruby-service-objects-and-oop]]; рабочая версия — 3.3.x).
- `Gemfile` с группой `:development, :test`:
  - `rubocop`
  - `rubocop-rspec`
  - `rubocop-performance`
- `.rubocop.yml`:
  - `TargetRubyVersion: 3.3`
  - `NewCops: enable`
  - `Style/FrozenStringLiteralComment: EnforcedStyle: always`
  - `Layout/LineLength: Max: 120`
  - `Style/Documentation: Enabled: false` (соответствует политике «no comments»
    из CLAUDE.md / Constitution).

## 3. Когда запускать

- **После `implement`**: до того как агент закроет фазу `implement`,
  он обязан выполнить `bundle exec rubocop` и получить **zero offenses**.
  Если есть ошибки — фаза не считается завершённой.
- **На `verify`**: lint входит в обязательный набор проверок стадии
  `verify`. Падение rubocop = падение verify.
- **На `review`**: ревьюер обязан убедиться, что lint clean
  (`bundle exec rubocop`) перед approve.

## 4. Команды

- `bundle exec rubocop` — стандартный прогон.
- `bundle exec rubocop --autocorrect` (`-a`) — безопасный autocorrect.
  Использовать свободно; коммитить отдельным коммитом «chore: rubocop -a».
- `bundle exec rubocop --autocorrect-all` (`-A`) — небезопасный autocorrect.
  **Только** после ручного просмотра diff'а; запрещён в автоматическом
  режиме внутри KOS-агента без явного подтверждения человеком.
- `bundle exec rubocop path/to/file.rb` — точечный прогон во время
  отладки cops; не заменяет финального полного прогона.

## 5. Disable-политика

- **Inline `# rubocop:disable Cop/Name`** допустим, если рядом есть
  комментарий, объясняющий, почему правило отключено для конкретного
  места. Без комментария — лучше переписать код.
- **Project-wide disable** (правка `.rubocop.yml`, `Enabled: false`
  или ужесточение/ослабление `Max`) **запрещён без апдейта этой статьи**.
  Изменение `.rubocop.yml` сопровождается коммитом + обновлением body
  этой knowledge article через `update_knowledge_entry`.

## 6. Новые версии

- Апгрейд `rubocop` / extensions — `bundle update rubocop rubocop-minitest
  rubocop-performance` в отдельной задаче. Новые cops по умолчанию
  включены (`NewCops: enable`), так что апгрейд может потребовать
  точечного фикса.

## 7. Что НЕ покрывает RuboCop

- Тесты — отдельный набор (RSpec; см.
  [[owl-ruby-testing-and-public-api-coverage]]).
- Семантические инварианты Owl (workflow, артефакты) — `owl config validate`
  и `owl artifact validate`.
- Архитектурные правила (фасад, namespace) — пока не enforce-ятся
  линтером; ловятся ревью. В перспективе — кастомный RuboCop cop.

## 8. Стоп-условия

- Если `bundle exec rubocop` падает с ошибкой инфраструктуры
  (не offenses, а stacktrace) — остановиться, не глушить через
  inline disable.
- Если кажется, что cop неуместен для всего проекта — открыть
  задачу на апдейт этой статьи, не править `.rubocop.yml` молча.

