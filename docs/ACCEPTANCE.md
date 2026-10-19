# Критерии приёмки MVP

Проверено 19.10.2026, 0.1.0 (1). Подробности и ограничения — [QA.md](QA.md). Метки synthetic/native/live указывают уровень доказательства; они не заменяют проверку установки на реальный второй телефон или clean-Mac test.

## Основной продукт

- [ ] Native app запускается на Apple Silicon/macOS 15 без внешнего iMazing, Homebrew и ipatool.
- [x] **Live GUI:** новый вход в собственном namespace; авторизованный запрос и скачивание Craftersy 5.1 прошли.
- [ ] Реальный экран/повтор неверного 2FA отдельно наблюдён; contract-путь проверен synthetic, пользователь завершил вход самостоятельно.
- [x] **Synthetic:** изоляция двух аккаунтов/cookies/credentials проверена Go tests. Второй live account остаётся pending.
- [x] **Live read-only:** iPhone 16 Pro Max / iOS 18.5, 333 приложения, включая 27 offloaded; иконки и metadata.
- [x] Чтение iOS 27 явно оставлено ограничением preview: такого live-устройства сейчас нет.
- [x] **Live GUI:** Craftersy 5.1 → собственная библиотека; bundle/version/build, SINF и независимый SHA-256 подтверждены; phone writes отсутствуют.
- [ ] Источник → другой телефон использует правильные app/version/account и UDID.
- [ ] Библиотека → телефон повторно использует архив без ненужного повторного скачивания.
- [ ] Успешная установка подтверждена readback bundle/version; проверка запуска записана отдельно.
- [x] **Synthetic:** существующая установленная копия пропускается до download/install; при recovery сначала readback.
- [x] **Implementation/native controls:** доступная альтернатива имеет отдельную кнопку подтверждения, автоматической подмены нет.
- [x] **Synthetic + implementation:** license/session/missing account переходят в waiting state; TestFlight не получает fake-download.

## Интерфейс

- [x] **Native synthetic:** три телефона рядом с библиотекой в обеих темах, роли не фиксированы; screenshots сохранены.
- [ ] Пять синтетических/реальных устройств в узком окне имеют читаемые колонки, навигацию и горизонтальную прокрутку.
- [ ] Поиск независим для каждой колонки, single/multi-select работают.
- [ ] Все три направления pointer drag-and-drop и batch проверены на живых телефонах. **Phone→library прошёл вручную**, matching cache повторно использован; два install-направления ждут второго телефона.
- [ ] Drag к краю позволяет добраться до скрытого устройства; есть keyboard/button equivalents.
- [x] **Native:** `⌘S`/кнопка библиотеки, очередь отдельно; worker не зависит от видимости панели.
- [x] **Native + preferences:** compact default; RU/light и видимость библиотеки сохранены после relaunch. Comfortable переключатель реализован; все комбинации плотности отдельно не прогонялись.
- [ ] Русский и английский не обрезают ключевые действия/ошибки; обе темы контрастны.
- [x] **Native:** Escape, outside coordinate click и Command-Tab закрывают popover; mutual exclusion реализован.
- [ ] Системный Keychain panel/меню не отменяют авторизацию неожиданно.
- [ ] Включение Reduce Motion/Transparency и Increase Contrast сохраняет понятность.
- [ ] Нативный вид соответствует approved screenshots; mock-frame, demo accounts и timer progress не попали в production.

## Очередь и файлы

- [ ] Разрыв USB во время скачивания/установки приводит к корректному состоянию, не к false success.
- [x] **Synthetic:** reconnect/retry сохраняет immutable target; live USB во время install ещё не проверен.
- [x] **Synthetic:** ошибки аккаунта/лицензии одного app не отменяют независимые задачи.
- [x] **Synthetic + C safety:** download cancel очищает staging; незапущенная задача отменяется; terminal install ожидается без объявления мгновенной отмены.
- [x] **Synthetic:** interrupted install требует retry/readback, уже установленное пропускается. Живой crash during install pending.
- [x] **Synthetic:** CRC damage, unsafe path, wrong bundle/version отвергаются до ready; проверен также реальный Avito IPA read-only.
- [x] **Synthetic:** manifest/operations reopen, vanished file → missing/no cache match. Реальный final-bundle relaunch также прошёл: библиотека/журнал/аккаунт сохранены (QA).
- [x] **Synthetic:** одинаковый IPA под разными account references хранится раздельно.

## Удаление

- [x] **Native single + implementation batch:** контекстное меню, панель выделения, `⌘⌫`; проверено на отдельном синтетическом IPA.
- [x] **Native:** подтверждение называет выбранный QA Fixture и объясняет сохранность телефонных приложений.
- [x] **Native GUI + FileManager:** тестовый IPA ушёл в Trash, индекс/объём обновились; исходник импорта сохранён.
- [x] **Synthetic:** queued reference и ещё не bound cache match защищены от удаления; failed/canceled staging не ready.
- [x] **Native GUI:** удалён только QA IPA; Craftersy, аккаунт и источник сохранены. Код library deletion не вызывает phone API.
- [x] Device uninstall deferred: UI-действия нет; необязательная функция не выдаётся за проверенную.

## Поставка

- [x] **Packaging:** 8 Mach-O, arm64, min macOS 15; third-party dylib paths переписаны в bundle, остальные системные.
- [x] Pinned revisions/SHA-256, THIRD_PARTY_NOTICES и scripts/README приложены.
- [x] Runtime данные находятся вне source и bundle; реальный скачанный IPA — в Application Support, QA logs — в ignored .build.
- [x] **Packaging:** codesign deep/strict проверяет app, helper и шесть dylib; notarization не заявлена.
- [ ] DMG монтируется, app переносится в Applications и запускается.
- [ ] Реальная чистая среда проверена; старые credentials/cache не маскируют отсутствие runtime assets.
- [ ] Gatekeeper проверен на quarantined артефакте; глобальное отключение защиты не требуется.
- [ ] Smoke test всего transfer-flow выполнен из `.app`, а не только из `swift run`/CLI.
- [x] README/STATUS/QA явно различают реализацию, synthetic, live read-only, live download и отсутствующие проверки.

Нельзя назвать приложение полностью готовым при незакрытом реальном GUI login, установке/readback или самостоятельной упаковке. При отсутствии внешнего условия допустима честно обозначенная preview-сборка с pending live checks.


## Визуальная доработка 0.1.1 (19.10.2026)

- [x] Нейтральные mouse selection/hover, один отдельный keyboard focus contour; постоянные зелёные обводки и ready-галочки IPA удалены.
- [x] Toolbar, поиск, колонки, выбор, очередь, настройки и аккаунты приведены к обновлённым правилам DESIGN.md.
- [x] Финальный GUI: Tab, Command-click, Shift-range, поиск, RU/EN, обе темы/плотности, ⌘S/⌘J, Escape/outside click, подтверждение удаления с отменой.
- [x] Native synthetic композиции 3 устройств и 5 с overflow сохранены отдельно от live evidence.
- [x] Повторное использование Craftersy IPA через явное действие; файл остался один, новых установок/удалений на телефоне нет.
- [x] Новый `.app`/DMG 0.1.1, signature/closure/source digest, mount и relocated read-only diagnostics проверены.
- [ ] Свежий manual pointer drop: автоматические попытки inconclusive; live установка на второй телефон, clean Mac/Gatekeeper и полная accessibility matrix остаются открытыми.

Свежие результаты и hashes — в начале docs/QA.md; более ранние Core/helper/Trash suites в этом документе сохраняют свой уровень и дату проверки.


## Очередь 0.1.2 (19.10.2026)

- [x] Drag-resize верхнего разделителя и сохранение высоты после relaunch проверены в GUI.
- [x] Эффективная высота ограничена окном/плотностью; native minimum-window fixture сохраняет список библиотеки.
- [x] Newest-first UI, retry recency, legacy migration и стабильность progress/completion проверены; FIFO worker сохранён.
- [x] Expanded feedback/row highlight/scroll-to-new-job и collapsed header acknowledgment проверены на существующем IPA.
- [x] Pending duplicate outcome покрыт synthetic Core; 22 tests / 115 assertions / 0 failures.
- [x] Данные пользователя сохранены, три cache-only smoke-задачи завершены, phone writes отсутствуют.
- [x] Финальные app/DMG 0.1.2 собраны/проверены, app оставлена открытой; свежие hashes в начале docs/QA.md.


## Захват высоты очереди 0.1.3 (19.10.2026)

- [x] Full-width 20 pt band; AppKit owns cursor and native drag.
- [x] Mouse capture near both vertical edges and away from center, arrow-key adjustment, collapse/reopen, persisted height after relaunch.
- [x] Native minimum-window fixture retains library content; extra 10 pt included in height cap.
- [x] App/DMG 0.1.3 (4) build/signature/closure/source digest/mount/relocation verified; app opened.
- [ ] Automated visual cursor-flicker measurement unavailable in CUA; this narrow limitation is recorded in QA.

No phone mutation or new transfer was needed. Existing live-install/clean-Mac gaps remain unchanged.


## Переименование 0.1.4 (19.10.2026)

- [x] Видимое имя приложения и DMG обновлено; stable storage/Keychain IDs сохранены.
- [x] GUI после подтверждения доступа Keychain показывает прежний аккаунт, восемь IPA и историю; manifest/operations/preferences не изменились.
- [x] RU/EN README, текущий handoff, инструкции GitHub и сборки обновлены; исторические материалы отмечены.
- [x] Core22/115, Go race/vet, C sanitizer checks, native bundle/DMG integrity и relocated helper hello пройдены.
- [x] Длинное имя проверено в minimum light/EN и normal dark/RU synthetic layouts.
- [ ] Private GitHub/release/fresh clone: окончательный readback см. STATUS/QA после публикации.

Эта поставка остаётся preview: второй телефон/live install/readback/launch, второй live аккаунт и clean-Mac/Gatekeeper остаются открытыми.
