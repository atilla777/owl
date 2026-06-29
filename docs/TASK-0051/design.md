---
status: shipped
summary: "Детект self-hosted source-репозитория через presence-check (owl-cli.gemspec + lib/owl/version.rb под root) в новом Owl::Version::Internal::SelfHosted; Owl::Version::Api.info при self_hosted берёт project из Owl::VERSION, ставит self_hosted: true и up_to_date: true, config не пишет."
---

# Context

`Owl::Version::Api.info(root:)` (`lib/owl/version/api.rb`) сейчас читает стэмп
`owl.version` через `Owl::Config::Api.read_key` и сравнивает его с
`Owl::VERSION`:

```ruby
gem:        Owl::VERSION,
project:    project,                         # из config owl.version
up_to_date: !project.nil? && project == Owl::VERSION
```

CLI-обёртка `lib/owl/cli/internal/commands/version.rb` уже резолвит project
root (`resolve_root`) и передаёт его в `info(root:)`, печатая `gem` / `project`
/ `up_to_date`. Версионный домен — тонкий фасад без backend-стека (в отличие от
`tasks` / `config`): у него нет `backend.rb` / `internal/`. По §6 архитектуры
файловая деталь (есть ли в root признаки source-дерева) должна жить в
`Owl::Version::Internal::*`, а не инлайном в фасаде.

Brief зафиксировал целевое поведение: в self-hosted source-репозитории
`Owl::VERSION` авторитетен, `self_hosted: true`, `up_to_date: true`, без записей
в config; consumer-поведение неизменно.

# Decision

1. **Новый сервис-объект `Owl::Version::Internal::SelfHosted`**
   (`lib/owl/version/internal/self_hosted.rb`) с `module_function`-методом
   `detect(root:) -> Boolean`. Признак self-hosted source-дерева —
   одновременное присутствие под разрешённым `root`:
   - `owl-cli.gemspec` (имя гема, специфичное для source-репо), и
   - `lib/owl/version.rb` (само определение `Owl::VERSION`).

   Оба условия должны выполняться (`File.file?` по `File.join(root, …)`); это
   максимально специфично к source-дереву Owl и не срабатывает в
   consumer-установках, где материализованы только `.owl/` / `tasks/` / `docs/`,
   но нет `lib/owl/` и gemspec. Проверка идёт по переданному `root`
   (разрешённому CLI), а не по `Dir.pwd`, поэтому запуск из подкаталога
   работает корректно.

2. **`Owl::Version::Api.info(root:)` ветвится по детекту:**

   ```ruby
   self_hosted = Owl::Version::Internal::SelfHosted.detect(root: root)
   if self_hosted
     Result.ok(gem: Owl::VERSION, project: Owl::VERSION,
               self_hosted: true, up_to_date: true)
   else
     result  = Owl::Config::Api.read_key(root: root, key: 'owl.version')
     project = result.ok? ? result.value[:value] : nil
     Result.ok(gem: Owl::VERSION, project: project, self_hosted: false,
               up_to_date: !project.nil? && project == Owl::VERSION)
   end
   ```

   `info` НЕ выполняет записей в config ни в одной ветке (read-only).

3. **CLI-обёртка** (`commands/version.rb`) добавляет `self_hosted:
   result.value[:self_hosted]` в JSON-payload и в человекочитаемый вывод даёт
   осмысленную строку для self-hosted случая (например, помечает, что это
   source-репозиторий и дрейфа нет), чтобы текстовый вывод не вводил в
   заблуждение.

4. **Версия / CHANGELOG.** Минорный бамп `Owl::VERSION` (аддитивное поле
   `self_hosted` + новое поведение) и запись в `CHANGELOG.md` в том же коммите.

# Alternatives

- **Авто-синк config (`owl.version = Owl::VERSION`) в self-hosted ветке.**
  Отклонено пользователем на шаге brief: даёт побочную запись в
  `.owl/config.yaml` при read-команде `owl version`; выбран read-only детект.
- **Детект только по `owl-cli.gemspec`.** Менее надёжно: gemspec может оказаться
  в нерелевантном дереве; пара (gemspec + `lib/owl/version.rb`) специфичнее и
  прямо связывает признак с определением `Owl::VERSION`.
- **Детект по имени каталога / git-remote.** Хрупко (переименование клона, иной
  remote, отсутствие git) и завязано на окружение, а не на содержимое source-
  дерева. Отклонено.
- **Инлайн `File.file?` прямо в `Api.info`.** Проще, но нарушает §6 (FS-деталь в
  фасаде вместо `Internal::*`) и хуже тестируется изолированно. Отклонено в
  пользу `Internal::SelfHosted`.

# Risks

- **Ложноположительная детекция** в consumer-проекте, случайно содержащем оба
  файла. Минимизировано требованием обоих специфичных признаков; consumer-
  установки Owl их не материализуют. Покрывается consumer-спекой.
- **Расширение JSON-контракта** `owl version` полем `self_hosted` —
  аддитивное; существующие ключи (`gem`, `project`, `up_to_date`) сохраняются.
  Потребители, читающие старые ключи, не ломаются. Минорный бамп это отражает.
- **Покрытие публичного API.** `lib/owl/version/api.rb` обязан иметь 100% line
  coverage; обе ветви (self-hosted / consumer) и `Internal::SelfHosted.detect`
  (true/false) должны быть покрыты RSpec — иначе падает coverage-гейт.

# API

Изменяемая / добавляемая публичная поверхность (публикуется в `docs/` на
`merge_docs`):

- `Owl::Version::Api.info(root:) -> Owl::Result` — теперь возвращает payload
  `{ gem:, project:, self_hosted:, up_to_date: }`. Новое поле:
  - `self_hosted` (Boolean) — `true`, только когда команда выполняется внутри
    self-hosted source-репозитория Owl (определяется по наличию `owl-cli.gemspec`
    и `lib/owl/version.rb` под `root`).
  - В self-hosted режиме `project == Owl::VERSION` и `up_to_date == true`
    независимо от стэмпа `owl.version`.
  - В consumer-режиме `project`, `up_to_date` сохраняют прежнюю семантику
    (стэмп `owl.version` vs `Owl::VERSION`).
- `owl version --json` CLI-контракт: добавляет ключ `self_hosted` к
  существующим `gem` / `project` / `up_to_date`.
- `Owl::Version::Internal::SelfHosted.detect(root:) -> Boolean` — внутренний
  сервис-объект (не часть кросс-доменного публичного API, но тестируемая
  единица детекции).
