# Owl Ruby code architecture

Extends [[owl-project-constitution]] §5.10.
Sibling rule: [[owl-ruby-service-objects-and-oop]].

---

# Owl Ruby code architecture

## 1. Назначение

Правило фиксирует доменно-ориентированную организацию Ruby-кода Owl CLI: какие
домены признаются, как именуются namespaces, какой публичный фасад каждый
домен предоставляет, как устроен **per-domain backend pattern** (api → backend →
backends/filesystem → internal → local), и как оформляются возвраты публичного
API. Это не каноническая DDD-методология (без aggregates / domain events /
repositories в обязательной форме), а **modular, domain-oriented architecture** —
discipline границ доменов.

## 2. Перечень доменов

Границы доменов зафиксированы и не торгуются на ходу. Если работа требует
нового домена — это отдельное решение, оформляется обновлением этого правила.

Домены живут в `lib/owl/<domain>/`. Каждый — отдельный namespace `Owl::<Domain>`.
Основные:

- `Owl::Config` — чтение/валидация `.owl/config.yaml` и реестров (`workflows.yaml`,
  `artifacts.yaml`).
- `Owl::Workflows` — реестр и схемы workflow, граф шагов и артефактов.
- `Owl::Artifacts` — реестр типов артефактов, шаблоны, JSON Schema валидация.
- `Owl::Tasks` — task state, index, parent/child, текущая задача.
- `Owl::Steps` — Step invocations, ready/blocked steps, активный step-lock.
- `Owl::Storage` — storage resolver (логические роли → физические пути),
  адаптеры файлового backend.
- `Owl::Validation` — structural / semantic валидация артефактов.
- `Owl::Specs` — project-level, domain-addressed living specs (`specs/<domain>/spec.md`):
  read / resolve / validate через `specs` storage role.
- `Owl::Locks` — межсессионные блокировки (push-lock и пр.).
- `Owl::Publish` — публикация знания в `docs/` по правилам `publishes:`.
- `Owl::Subagents` — output-спецификации и report-пути для исполнения шагов в
  изолированных subagent-сессиях.
- `Owl::Cli` — тонкий entry-point: парсинг аргументов, JSON-вывод, exit codes.

Помимо них есть операционные домены-команды (`Owl::Archive`, `Owl::CommitPush`,
`Owl::Context`, `Owl::Init`, `Owl::Instructions`, `Owl::Orchestration`,
`Owl::Recall`, `Owl::Status`, `Owl::Upgrade`, `Owl::Verification`) и
**cross-cutting** namespace `Owl::Internal::*` (см. §6) — он не домен, а набор
bootstrap-хелперов, общих для всех доменов.

## 3. Per-domain backend pattern

Owl **не** имеет единого «storage god-object», через который проходит весь
файловый I/O. `Owl::Storage` — это **один домен среди многих**, отвечающий за
резолвинг логических ролей хранения в физические пути; он не является
универсальной воронкой для чтения/записи каждого другого домена. Каждый домен,
которому нужен persistence, владеет **собственным backend-стеком**.

Канонический пример — `Owl::Tasks` (`lib/owl/tasks/`):

```
lib/owl/tasks/
  api.rb                      # Owl::Tasks::Api          — публичный фасад
  backend.rb                  # Owl::Tasks::Backend      — интерфейс (contract)
  backends/
    filesystem.rb             # Owl::Tasks::Backends::Filesystem — v1 impl
  internal/
    task_reader.rb            # Owl::Tasks::Internal::*  — мелкие сервис-объекты
    index_writer.rb
    ...
  local.rb                    # Owl::Tasks::Local        — value-объекты путей
```

Поток вызова и ответственность каждого слоя:

1. **`Owl::<Domain>::Api`** — публичный фасад. Единственная поверхность, на
   которую опираются другие домены и CLI. Метод фасада выбирает backend через
   `Owl::Internal::BackendResolver.resolve(root:, scope: :<domain>)`, делегирует
   операцию backend-инстансу и возвращает `Owl::Result` (см. §5). Типичная
   обёртка:

   ```ruby
   def with_backend(root)
     backend_result = Owl::Internal::BackendResolver.resolve(root: root, scope: :tasks)
     return backend_result if backend_result.err?

     yield backend_result.value
   end
   ```

2. **`Owl::<Domain>::Backend`** — интерфейс-модуль (contract). Перечисляет
   instance-методы backend и `raise NotImplementedError` по умолчанию. Будущие
   backends (Obsidian, SQLite, remote) реализуют те же сигнатуры. Backend
   конструируется для конкретного `root:` и не повторяет его в каждом вызове.

3. **`Owl::<Domain>::Backends::Filesystem`** — v1-реализация интерфейса. Это
   **тонкий делегатор**: каждый публичный метод собирается из вызовов мелких
   `Internal::*` сервис-объектов (`Internal::Paths.resolve`,
   `Internal::IndexReader.read`, …), а не несёт инлайновую бизнес-логику.
   `Owl::Tasks::Backends::Filesystem` — эталон этого стиля; новые backends
   должны на него ориентироваться.

4. **`Owl::<Domain>::Internal::*`** — мелкие сервис-объекты домена (по одному
   действию: читатель индекса, писатель статуса, генератор id и т.д.). Это
   приватные детали реализации backend; см. правила стиля в
   [[owl-ruby-service-objects-and-oop]].

5. **`Owl::<Domain>::Local`** — value-объекты (`Data.define`), несущие
   абсолютные пути, которые пишет **именно filesystem-backend** (`task.yaml`,
   `index.yaml`, pointer). Публичные payload-ы фасада **очищаются** от path-ключей
   (`STRIPPED_PATH_KEYS`), чтобы не-filesystem backends могли удовлетворять тому
   же контракту без синтетических путей; кто реально нуждается в путях,
   обращается к рефлексии (`Api.local_paths(...)`). `local.rb` присутствует
   только у доменов с локальной runtime-проекцией (`tasks`, `artifacts`,
   `workflows`).

Backend-стек (`backend.rb` + `backends/filesystem.rb`) на сегодня имеют домены
`artifacts`, `config`, `locks`, `publish`, `storage`, `tasks`, `validation`,
`workflows`. Выбор активного backend для домена определяется
`settings.storage.backend` в `.owl/config.yaml` и резолвится централизованно
через `Owl::Internal::BackendResolver` (см. §6).

## 4. CLI как тонкий адаптер

`Owl::Cli::*` отвечает только за:

- парсинг аргументов командной строки (Thor / OptionParser);
- конвертацию входных строк в типизированные параметры;
- вызов соответствующего метода `Owl::<Domain>::Api`;
- сериализацию результата (JSON, человеческий вывод);
- exit codes (`0` на `Owl::Result::Ok`, ненулевые — на `Owl::Result::Err`).

В `Owl::Cli::*` запрещены:

- бизнес-логика;
- чтение/запись файлов напрямую (только через фасад соответствующего домена —
  обычно `Owl::Storage::Api` для произвольных путей либо `Owl::<Domain>::Api`
  для доменных данных);
- знание о форме `.owl/`, `tasks/`, `docs/` (это знание лежит в backend-ах
  доменов).

**Целевое правило слоёв:** `cli/` вызывает домены **только** через
`Owl::<Domain>::Api`, а не через `Owl::<Domain>::Internal::*`. Доменный
`Internal::*` — приватная деталь реализации backend, и адаптер не должен в неё
тянуться.

> Заметка о текущем состоянии: на момент написания в `lib/owl/cli/` остаётся
> ~24 прямых обращения в доменный `Internal::*` (доминирует
> `Steps::Internal::ActiveStepLock`). Это **долг**, который выпрямляется
> отдельным workstream-ом — каждому такому обращению добавляется additive-метод
> в соответствующем `Api`-фасаде. Документ описывает целевое правило, к которому
> сходится кодовая база. Исключение — `Owl::Cli::Internal::*` (собственный
> internal самого cli, напр. `UserFileReader`): это не cross-domain reach и под
> запрет не попадает.

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

- `Owl::Result.ok(value)` / `Owl::Result::Ok.new(value:)` — успех; `value` —
  `Data.define`-структура домена или примитив.
- `Owl::Result::Err.new(code:, message:, details:)` — ошибка; `code` —
  `Symbol` из перечня кодов домена (`Owl::Tasks::ErrorCodes` или эквивалент),
  `message` — человеко-читаемая строка, `details` — `Hash` с диагностикой.

Внутри домена сервисы могут оперировать обычными значениями и исключениями;
конвертация в `Owl::Result` происходит на уровне фасада (и `backends/filesystem`,
который тоже возвращает `Result`, прокидывая `.err?` наружу).

Использование `dry-monads` или сторонних Result-библиотек **запрещено**
(см. правило зависимостей в [[owl-ruby-service-objects-and-oop]]).

## 6. Cross-cutting bootstrap: `Owl::Internal::*`

Помимо доменов есть **не-доменный** namespace `Owl::Internal::*`
(`lib/owl/internal/`) — общие bootstrap-хелперы, которыми пользуются все домены.
Это **легитимные** исключения из правила «весь I/O через backend домена», потому
что они обслуживают сам выбор/загрузку backend-ов и не могут сами через них
проходить без циклической зависимости. Каждый помечен в шапке как
«Layer-A/B/C bootstrap exception».

- **`BackendResolver`** (`backend_resolver.rb`) — резолвит активный backend для
  `scope` (домена) из `.owl/config.yaml`. Три явных исключения, задокументированы
  в шапке файла:
  - **#1** `read_backend_name` читает `.owl/config.yaml` напрямую
    (`Pathname#read` + `YAML.safe_load`), а не через `Owl::Config::Api` /
    `Owl::Storage::Api`: выбор storage-backend сам зависит от конфиг-файла, так
    что маршрутизация чтения конфига через backend создала бы неразрешимый
    chicken-and-egg цикл. Это **единственное** каноническое место такого
    исключения.
  - **#2** `scope: :config` всегда резолвится в
    `Owl::Config::Backends::Filesystem`, независимо от
    `settings.storage.backend`: домен config *и есть* bootstrap — он должен быть
    читаем раньше любого селектора backend.
  - **#3** gem-shipped ассеты (bundled JSON schemas, seed-источники workflow/
    artifact) читаются через `Owl::Internal::GemAssets`, а не через
    `Owl::Storage::Api` — они лежат в install-директории гема, а не в проектной
    storage-роли, поэтому маршрутизация через storage-backend была бы category
    error.
- **`GemAssets`** (`gem_assets.rb`) — каноническое место чтения файлов,
  поставляемых внутри гема (схемы, seed-источники). Принимает опциональный
  `repo_root:` как test-seam; продакшен-вызовы читают из install-директории
  гема. Любой не-bootstrap код, которому нужны bundled-ассеты, обязан идти через
  `GemAssets`, а не реплицировать `File.read` по абсолютным путям.
- **`SeededLoader`** (`seeded_loader.rb`) — поверх `GemAssets`: разворачивает
  seed-директорию в список `{ relative_path:, contents: }` для материализации в
  проект.
- **`Paths`** (`paths.rb`) — корень репозитория/гема и путь к `schemas/`;
  крошечный helper, нужный до того, как доступны какие-либо backend-ы.
- **`Cache`** (`cache.rb`) — потокобезопасный process-local кэш
  (`fetch(key, version_token:)`), общий для доменных загрузчиков реестров;
  инвалидируется по version-токену.
- **`CycleDetector`** (`cycle_detector.rb`) — обобщённый DFS-детектор циклов в
  ориентированном графе. Извлечён из workflow graph builder, чтобы один и тот же
  обход (`requires` шагов workflow и cross-task `blocked_by`) не дублировался.

Общее правило: новый код **не** добавляет сюда сырые FS-чтения и не реплицирует
исключения — перечисленные модули и есть единственные санкционированные точки.

## 7. File / folder layout

```
lib/
  owl/
    result.rb                       # Owl::Result::Ok / Err
    internal/                       # cross-cutting bootstrap (НЕ домен)
      backend_resolver.rb           #   Owl::Internal::BackendResolver
      gem_assets.rb                 #   Owl::Internal::GemAssets
      seeded_loader.rb              #   Owl::Internal::SeededLoader
      paths.rb  cache.rb  cycle_detector.rb
    config/
      api.rb                        # Owl::Config::Api
      backend.rb
      backends/filesystem.rb
      internal/
    tasks/                          # эталон per-domain backend pattern
      api.rb                        # Owl::Tasks::Api
      backend.rb                    # Owl::Tasks::Backend (интерфейс)
      backends/
        filesystem.rb               # Owl::Tasks::Backends::Filesystem (impl)
      error_codes.rb                # Owl::Tasks::ErrorCodes
      local.rb                      # Owl::Tasks::Local (value-объекты путей)
      internal/
        task_reader.rb
        index_writer.rb
        ...
    workflows/  artifacts/  storage/  validation/  steps/  ...
      api.rb  backend.rb  backends/filesystem.rb  internal/  [local.rb]
    cli/
      runner.rb                     # bin/owl entry
      commands/
        task.rb  step.rb  ...
bin/
  owl                               # exec'ит Owl::Cli::Runner
spec/
  spec_helper.rb
  owl/
    result_spec.rb
    tasks/
      api_spec.rb
      internal/
        task_reader_spec.rb
```

Тестовый каталог — `spec/`. Owl — не Rails, поэтому предупреждение
Constitution §5.2 про конфликт `spec/` с RSpec не применимо. Test framework —
RSpec; правила юнит-тестов и покрытия публичного API см.
[[owl-ruby-testing-and-public-api-coverage]].

## 8. Запрещено

- Прямой `require`/вызов классов из `Owl::<Domain>::Internal::*` за пределами
  своего домена (включая `cli/` → доменный `Internal::*` — см. §4).
- Бизнес-логика в `Owl::Cli::*` или в Thor-командах.
- File / ENV / exec / HTTP I/O в фасаде или в `Owl::Cli` — только через backend
  своего домена либо санкционированные `Owl::Internal::*` bootstrap-хелперы (§6).
- Новые сырые FS-чтения в обход backend-ов и помимо исключений §6.
- Превращение `Owl::Storage` в универсальную воронку для I/O других доменов:
  каждый домен владеет собственным backend-стеком.
- Глобальные singleton'ы. Единственное исключение — `Owl::Config.current`
  как явно обсуждаемая конструкция конфига.

## 9. Тестирование

- Test framework — RSpec; layout, конфиг SimpleCov, правила 100% покрытия
  публичного API (`lib/owl/**/api.rb`) — см.
  [[owl-ruby-testing-and-public-api-coverage]].
- Юнит-тесты домена бьют по фасаду `Owl::<Domain>::Api` (поведенческие)
  либо по конкретному `Internal::*` сервису / `Backends::Filesystem` (изоляция
  логики).
- Cross-domain зависимости мокаются **только** на уровне фасадов
  (`Owl::Storage::Api`, `Owl::Tasks::Api`, …). Никаких моков на
  `Owl::Tasks::Internal::*` из тестов другого домена.

## 10. Эволюция правила

- Добавление нового домена — обновление §2 и архитектурного дерева в §7.
- Добавление нового backend (Obsidian / SQLite / remote) — реализация
  `Owl::<Domain>::Backend` контракта и регистрация в
  `Owl::Internal::BackendResolver`; форма фасада и `Owl::Result` не меняются.
- Изменение формы возврата (`Owl::Result`) — обновление §5 + §5.10 конституции.
- Новое исключение из правила «весь I/O через backend домена» оформляется как
  явный `Owl::Internal::*` helper с «Layer-A/B/C bootstrap exception» в шапке и
  поправкой к §6 — а не локальным решением в PR.
