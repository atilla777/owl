# Goal

Сделать так, чтобы `owl version` в self-hosted source-репозитории Owl не
показывал ложный дрейф: распознавать source-дерево, считать `Owl::VERSION`
авторитетным значением `project`, возвращать `self_hosted: true` и
`up_to_date: true` без записей в config; consumer-поведение неизменно. Подход и
поверхность зафиксированы в `design.md`.

## Scope

Версионный домен (`lib/owl/version/**`), CLI-обёртка `owl version`, версия гема
и CHANGELOG, плюс RSpec-покрытие обеих веток. Никаких изменений в config-домене,
init/upgrade, или других командах.

## Checklist

- [ ] `lib/owl/version/internal/self_hosted.rb` — новый сервис-объект
  `Owl::Version::Internal::SelfHosted` с `module_function` `detect(root:)`,
  возвращающим `true` ⇔ под `root` существуют одновременно `owl-cli.gemspec` и
  `lib/owl/version.rb` (через `File.file?(File.join(root, …))`). `# frozen_string_literal: true`.
- [ ] `lib/owl/version/api.rb` — `require_relative 'internal/self_hosted'`; в
  `info(root:)` ветвление: при `SelfHosted.detect(root:)` →
  `Result.ok(gem: Owl::VERSION, project: Owl::VERSION, self_hosted: true, up_to_date: true)`;
  иначе прежняя логика (читать `owl.version`), но добавить `self_hosted: false`
  в payload. Никаких записей в config.
- [ ] `lib/owl/cli/internal/commands/version.rb` — пробросить
  `self_hosted: result.value[:self_hosted]` в `JsonPrinter.success`; в
  человекочитаемой ветке (если есть) дать осмысленную строку для self-hosted
  (source-репозиторий, дрейфа нет).
- [ ] `lib/owl/version.rb` — бамп `VERSION` `1.2.0` → `1.3.0` (минор).
- [ ] `CHANGELOG.md` — новая секция `## [1.3.0] - 2026-06-29` с записью про
  `self_hosted`-детект в `owl version` (TASK-0051).
- [ ] `spec/owl/version/api_spec.rb` — добавить примеры: (a) self-hosted root
  (создать `owl-cli.gemspec` + `lib/owl/version.rb` в tmp-root) → `project ==
  Owl::VERSION`, `self_hosted: true`, `up_to_date: true` даже при устаревшем
  стэмпе; (b) consumer root → `self_hosted: false`, прежняя drift-семантика;
  обновить существующие примеры, чтобы они ожидали ключ `self_hosted: false`.
- [ ] `spec/owl/version/internal/self_hosted_spec.rb` — новый спек на
  `detect`: true при обоих файлах, false при отсутствии любого из них.
- [ ] `spec/owl/cli/api_spec.rb` — обновить/добавить пример для `owl version`,
  проверяющий присутствие ключа `self_hosted` в JSON-выводе.

## Constraints

- Архитектура §6: FS-деталь детекции живёт в `Owl::Version::Internal::*`, фасад
  `Api.info` остаётся тонким (`docs/agents/27_Owl_Ruby_code_architecture.md`).
- `Api.info` строго read-only — никаких записей в `.owl/config.yaml`.
- JSON-контракт аддитивен: ключи `gem` / `project` / `up_to_date` не
  переименовывать; только добавить `self_hosted`.
- 100% line coverage для `lib/owl/version/api.rb` (обе ветви)
  (`docs/agents/30_Owl_Ruby_testing_RSpec_and_public_API_coverage.md`).
- RuboCop зелёный (`docs/agents/29_Owl_Ruby_linting_RuboCop.md`).
- Бамп `Owl::VERSION` + CHANGELOG в том же коммите
  (`docs/agents/23_Owl_Project_Constitution.md` §7.1).

## Files to inspect

- `lib/owl/version/api.rb` — текущая `info`.
- `lib/owl/version.rb` — константа.
- `lib/owl/cli/internal/commands/version.rb` — CLI-обёртка и `resolve_root`.
- `lib/owl/config/api.rb` — `read_key` (используется в consumer-ветке).
- `spec/owl/version/api_spec.rb`, `spec/owl/cli/api_spec.rb` — существующие
  тесты и хелперы (`with_tmp_project`, `write`).

## Tests and verification

- `bundle exec rspec spec/owl/version spec/owl/cli/api_spec.rb` — зелёные.
- `bundle exec rspec` — полный прогон зелёный, coverage-гейт по
  `lib/owl/**/api.rb` = 100%.
- `bundle exec rubocop` — без нарушений.
- `bin/owl version --json` в этом репозитории → `self_hosted: true`,
  `up_to_date: true`, `project == gem`.

## Smoke test

```
bin/owl version --json
# ожидаем: { "ok": true, "gem": "1.3.0", "project": "1.3.0",
#            "self_hosted": true, "up_to_date": true }
```

## Out of scope

- Авто-синк / запись `owl.version` в config (отклонено на brief).
- Изменения в `owl init` / `owl upgrade` стэмпинге.
- Детект через git-remote или имя каталога.
- Любые другие команды, кроме `owl version`.
