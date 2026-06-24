# Goal

Сделать так, чтобы свежий `owl init` / `owl upgrade` в consumer-проекте получал все
5 workflow (`feature`, `composite_feature`, `hotfix`, `refactor`, `quick`) с
`source_present: true` и рабочую ссылку на Requirement/Scenario грамматику — устранив
расхождение между догфуд-копией `.owl/workflows/` и тем, что реально пакуется в gem.

# Scope

- Промоция сидов workflow `hotfix`/`refactor`/`quick` из `.owl/workflows/` в корневой
  `workflows/` (источник, который пакует gemspec и копирует `SeededLoader`).
- Согласование реестра по умолчанию (`DefaultTemplate.render`) с поставляемыми сидами.
- Доставка Requirement/Scenario грамматики в consumer (встроить в сидируемый контекст
  brief — предпочтительно — либо засидить doc-файл).
- Bump `Owl::VERSION` + `CHANGELOG.md`.

# Constraints

- `SeededLoader.load(source_dir: 'workflows', target_prefix: '.owl/workflows')` копирует
  ровно содержимое корневого `workflows/`. Значит сиды должны лежать там, а не только в
  `.owl/workflows/`.
- `DefaultTemplate.render` — хардкод-heredoc реестра; каждый зарегистрированный ключ
  обязан иметь существующий `source:`-файл в сборке (иначе свежий init даёт битый реестр).
- Managed-провенанс: `hotfix`/`refactor`/`quick` помечаются `managed: true` (Owl-shipped,
  upgrade-safe; кастомизация клонированием). Это закрывает открытый вопрос про `quick`
  из brief: делаем его `managed: true` сидом (а не «зарегистрирован, но не доставляется»).
- Грамматика: не должна отставать от канона. Предпочесть самодостаточный встроенный текст
  в сидируемом brief-контексте, чтобы не плодить отдельный недоставляемый файл.
- Не трогать пользовательские `managed:false` сущности и overlays при upgrade.

# Checklist

1. Скопировать `.owl/workflows/hotfix/` → `workflows/hotfix/` (workflow.yaml + все
   `*.context.md`). То же для `refactor/` и `quick/`. Сверить, что `workflow.yaml`
   ссылается только на присутствующие `context_file`.
2. В `lib/owl/workflows/internal/default_template.rb` → `render`: добавить в heredoc
   записи реестра `hotfix`, `refactor`, `quick` (все `managed: true`, с `source:` на
   соответствующие `workflows/<id>/workflow.yaml`, version "1.0").
3. Грамматика для consumer: добавить компактный раздел «Requirement/Scenario grammar»
   (RFC-2119 `### Requirement:` + `#### Scenario:` с UPPERCASE `- WHEN` / `- THEN`) в
   сидируемые brief-контексты `workflows/{feature,composite_feature,hotfix,refactor}/
   brief.*.context.md` и `workflows/quick/brief.context.md`; в `.owl/artifacts/brief/
   artifact.yaml` заменить голую ссылку на `docs/agents/31_…` на «см. встроенную грамматику
   в контексте шага brief» (оставив док как расширенный канон в репо Owl).
4. Проверить, что `gemspec` уже пакует `workflows/**/*` (да) — новые файлы попадут
   автоматически; ничего в gemspec менять не нужно, если только грамматика не выносится в
   отдельный засидаемый файл (тогда добавить glob).
5. Bump `Owl::VERSION` (minor — новый consumer-facing контент сидов) + запись в
   `CHANGELOG.md`.
6. RSpec: добавить/обновить тест, что `DefaultTemplate`/реестр перечисляет 5 workflow и
   каждый `source:` существует среди сидов `SeededSources.files`.

# Files to inspect

- `workflows/` (корень) — целевой сид; `.owl/workflows/{hotfix,refactor,quick}/` — источник копии.
- `lib/owl/workflows/internal/default_template.rb` — реестр по умолчанию.
- `lib/owl/workflows/internal/seeded_sources.rb`, `lib/owl/internal/seeded_loader.rb`,
  `lib/owl/internal/gem_assets.rb` — механика сидов (чтение/копирование).
- `.owl/artifacts/brief/artifact.yaml` + `workflows/*/brief*.context.md` — ссылка на грамматику.
- `owl-cli.gemspec` — globs (`workflows/**/*` уже есть).
- `lib/owl/version.rb`, `CHANGELOG.md`.
- `spec/owl/workflows/` — тесты реестра/сидов.

# Tests and verification

- Юнит: тест, что дефолт-реестр содержит 5 ключей и для каждого `source:` присутствует
  в `SeededSources.files`/на диске.
- Юнит/инвариант: `gem build owl-cli.gemspec` включает `workflows/{hotfix,refactor,quick}/`.
- `bundle exec rspec` зелёный (после — `git checkout README.md` из-за известной
  test-isolation проблемы), 100% покрытие затронутых `**/api.rb` (если менялись).
- RuboCop net-zero на трогаемых файлах.

# Smoke test

```
gem build owl-cli.gemspec
# в /tmp пустом git-проекте:
owl init
owl workflow list --json   # → 5 workflow, у каждого source_present:true
owl workflow validate hotfix --json && owl workflow validate refactor --json && owl workflow validate quick --json
# открыть brief-контекст в проекте: грамматика Requirement/Scenario присутствует, ссылка не битая
```

# Out of scope

- F0.2 (лок `index.yaml`) и PF-фиксы (subcommand-help, scenario-валидация, takeover-hint,
  `--brief-body`) — отдельные задачи TASK-0021…0024.
- P1 трекер-функции (query/filter/deps/labels) — последующая волна.
- Авто-пропагация gem в consumer-проекты (CI) — P3.
