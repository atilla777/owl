---
status: resolved
summary: "owl version в self-hosted source-репозитории распознаёт source-дерево (owl-cli.gemspec + lib/owl/version.rb), считает Owl::VERSION авторитетным project, ставит self_hosted: true / up_to_date: true без записи в config; consumer-семантика дрейфа сохранена. Все проверки зелёные."
verdict: accepted
ready: true
---

# Summary

Ревью изменения TASK-0051: устранение ложного дрейфа `owl version` в
self-hosted source-репозитории Owl. Реализация полностью соответствует
утверждённым `brief` и `design`:

- Новый внутренний сервис-объект `Owl::Version::Internal::SelfHosted.detect(root:)`
  (`lib/owl/version/internal/self_hosted.rb`) распознаёт source-дерево по
  одновременному наличию под `root` файлов `owl-cli.gemspec` и
  `lib/owl/version.rb`. Детекция идёт по разрешённому `root`, а не `Dir.pwd`,
  поэтому запуск из подкаталога обрабатывается корректно.
- `Owl::Version::Api.info(root:)` ветвится по детектору: в self-hosted режиме
  возвращает `{ gem: Owl::VERSION, project: Owl::VERSION, self_hosted: true,
  up_to_date: true }`; иначе сохраняет прежнее gem-vs-stamp сравнение и
  добавляет `self_hosted: false`. Запись в config отсутствует в обеих ветвях.
- CLI-обёртка `owl version` пробрасывает `self_hosted` в JSON-payload рядом с
  существующими `gem` / `project` / `up_to_date` — аддитивное расширение
  контракта.
- `Owl::VERSION` бампнут `1.2.0` → `1.3.0`, добавлена секция `[1.3.0]` в
  `CHANGELOG.md` в том же изменении (минорный бамп — корректно для аддитивного
  поля + нового поведения).

# Findings

Проверены все пункты acceptance criteria брифа и решения дизайна.

1. **Корректность self-hosted детекции (both-files requirement).** OK.
   `detect` требует оба `File.file?` (gemspec И version.rb), что исключает
   ложноположительное срабатывание от случайного gemspec. Покрыто спеком
   `spec/owl/version/internal/self_hosted_spec.rb`: true при обоих файлах,
   false при отсутствии любого из них или обоих (4 примера).

2. **Авторитетность Owl::VERSION в self-hosted ветке.** OK. `info` возвращает
   `project: Owl::VERSION` и `up_to_date: true` независимо от устаревшего
   стэмпа. Проверено вживую: `bin/owl version --json` →
   `{"gem":"1.3.0","project":"1.3.0","self_hosted":true,"up_to_date":true}`,
   тогда как `.owl/config.yaml` хранит более старый `owl.version`.

3. **Сохранение consumer drift-семантики.** OK. Не-self-hosted ветка не
   изменена логически: читает `owl.version` через `Config::Api.read_key`,
   `up_to_date = !project.nil? && project == Owl::VERSION`; добавлено лишь
   `self_hosted: false`. Покрыто тремя consumer-примерами (match / drift /
   legacy nil-stamp) в `spec/owl/version/api_spec.rb`.

4. **Read-only / отсутствие записей в config.** OK. Ни одна ветвь `info` не
   пишет в `.owl/config.yaml`. Есть прямой регрессионный спек «does not write
   to .owl/config.yaml» — после `info` стэмп `version: '0.0.1'` остаётся.

5. **Аддитивность JSON-контракта.** OK. Ключи `gem` / `project` /
   `up_to_date` не переименованы и не удалены; добавлен только `self_hosted`.
   Минорный бамп это отражает.

6. **100% line coverage `lib/owl/**/api.rb`.** OK. Прямой разбор
   `coverage/.resultset.json`: `lib/owl/version/api.rb` — 14/14 строк,
   `lib/owl/version/internal/self_hosted.rb` — 9/9 строк, ни одной пропущенной.
   Обе ветви `info` и оба исхода `detect` покрыты.

7. **Архитектура §6 (FS-деталь в Internal).** OK. Проверка наличия файлов
   (`File.file?`) живёт в `Owl::Version::Internal::SelfHosted`, фасад
   `Api.info` остаётся тонким. Соответствует
   `docs/agents/27_Owl_Ruby_code_architecture.md`.

8. **Легитимность изменения constitution-allowlist.** OK. В
   `spec/owl/constitution/no_direct_fs_spec.rb` добавлена запись
   `version/internal/self_hosted.rb` — санкционированный механизм для нового
   Internal-файла, выполняющего прямой FS-ввод/вывод (`File.file?`). Это и есть
   предусмотренный allowlist для backend/internal-слоя.

9. **RuboCop.** OK. `bundle exec rubocop` — 530 файлов, 0 нарушений. Точечный
   `rubocop:disable Naming/PredicateMethod` на `detect` обоснован комментарием
   (имя-глагол зафиксировано дизайном и call-site'ами).

10. **Edge cases.** Legacy без стэмпа (consumer) → `project: null`,
    `up_to_date: false` (покрыто); запуск из подкаталога опирается на
    разрешённый `root` (детектор не использует `Dir.pwd`); ложноположительная
    детекция исключена требованием обоих специфичных файлов.

# Resolution

Замечаний, требующих изменений, не выявлено. Реализация, тесты, версия и
CHANGELOG согласованы с brief/design/plan. Все объективные проверки зелёные
(см. `verification.md`). Verdict: **accepted**.

# Remediation

Не требуется — блокирующих находок нет.

# Residual risks

- **Теоретический ложноположительный self-hosted** в consumer-проекте,
  случайно содержащем И `owl-cli.gemspec`, И `lib/owl/version.rb` в корне.
  Практически исключено: consumer-установки материализуют только
  `.owl/` / `tasks/` / `docs/`. Риск осознанно принят в дизайне.
- **Нет человекочитаемой (не-JSON) ветки** в `owl version` — команда всегда
  печатает JSON, поэтому критерий «текстовый вывод не вводит в заблуждение»
  выполняется тривиально (специального текстового рендера нет). Не дефект,
  фиксируется для прозрачности.
