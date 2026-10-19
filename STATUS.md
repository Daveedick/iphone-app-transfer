# Статус проекта

Обновлено: 19.10.2026. Сборка 0.1.4 (5), **preview с незавершёнными live-проверками**. Переименование в iPhone App Transfer и упаковка проверены; свежие результаты — ниже и в `docs/QA.md`.

## 19.10.2026 — публичный доступ

Пользователь прямо разрешил открыть репозиторий сразу, сохранив ограничения preview и незавершённые live-проверки. Это решение заменяет прежнее ожидание отдельного разрешения на public.

- [x] GitHub API подтверждает `isPrivate=false`, `visibility=PUBLIC` для [Daveedick/iphone-app-transfer](https://github.com/Daveedick/iphone-app-transfer).
- [x] Без GitHub-токена получены HTTP 200 для repository API, [релиза v0.1.4](https://github.com/Daveedick/iphone-app-transfer/releases/tag/v0.1.4), DMG и checksum. SHA-256 скачанного образа совпал с исходной сборкой: `64878b19d5cd1146be43b4c0ceeed0c8c392f3d9c64065658b5fd76b4d1b3105`.
- [x] Пометка private убрана из актуального описания репозитория и release notes. Статус prerelease сохранён; бинарники и тег не заменялись.

Проверка: `.build/qa/public-visibility/anonymous.json` (локальный ignored отчёт). Этот шаг проверяет публичную доступность, не установку на втором iPhone или чистом Mac. Лицензия собственного кода пока не выбрана; публичная видимость сама её не устанавливает. Старые разделы ниже сохраняют историю первоначальной приватной поставки.

## 19.10.2026 — 0.1.4 (5): iPhone App Transfer и приватная поставка

- [x] Видимое имя окна, меню, toolbar, локализаций, bundle metadata, `.app`, DMG и текущих документов — **iPhone App Transfer**. Внутренние Bundle ID, Keychain, preferences, library/cache и executable сохранены.
- [x] Полные RU/EN README и `docs/GITHUB_SETUP.md`; исторические screenshots/артефакты оставлены с прежними именами и датами.
- [x] Core portable: 22 tests / 115 assertions; Go helper race tests и vet; C-мост ASan/UBSan — pass. Это не XCTest и не live install.
- [x] Нативный GUI: новое имя окна/меню, сохранённый аккаунт, восемь IPA, прежние задачи, RU/dark/compact и высота очереди 254 pt доступны. Пользователь подтвердил системный запрос Keychain после обновления helper; повторный Apple login не выполнялся. Чтение registry не доказывает актуальность Apple-сессии.
- [x] SHA-256 manifest/operations/preferences совпал до/после запуска; количество IPA осталось восемь. Новые задачи, установки и удаления на телефонах не выполнялись. На момент этой проверки USB-телефон не определяется.
- [x] Native synthetic: новое длинное имя помещается в 760 × 560 pt light/EN и 1160 × 820 pt dark/RU; private QA captures находятся только в ignored `.build`.
- [x] Release `.app`/DMG: ad-hoc strict signature, 8 Mach-O / 6 dylib closure, read-only mount, Applications link, текущие notices/37 Go module licenses, source digest и relocated helper hello — pass. Gatekeeper/clean Mac этим не подтверждены.
- [x] Приватный GitHub `Daveedick/iphone-app-transfer` создан; API подтвердил `isPrivate=true`, `visibility=PRIVATE`. Исходный main совпал с локальным commit.
- [x] Приватный prerelease `v0.1.4` опубликован с DMG/checksum; оба файла скачаны обратно, SHA-256 совпал с локальным проверенным образом.
- [x] Свежий clone: все 327 tracked-файлов получены, release `.app` собран с нуля на том же Mac; runtime source SHA совпал. Это проверяет комплектность исходников, не clean Mac.
- [x] Staged privacy/link audit: собственные тексты и 13 PNG без найденных секретов/реальных inventory; IPA/auth/build files исключены. Vendored core сопоставлен с pinned module ZIP: 233 файла, только три заявленных cache-namespace изменения.

DMG: `dist/iPhone-App-Transfer-0.1.4-arm64.dmg`, 23563105 bytes, SHA-256 `64878b19d5cd1146be43b4c0ceeed0c8c392f3d9c64065658b5fd76b4d1b3105`. Runtime source SHA-256 `b986c80d1217ffcbcdcd8e1404f8dd83b238ba86aaa35f7ec1ba0dcc0c301ac3`. Технические отчёты без секретов: `.build/packaging-verification/rename-0.1.4/report.json`, `.build/qa/rename-0.1.4/preservation.json`, `publication.json`, `fresh-clone.json` в той же private QA-папке.

[Приватный репозиторий](https://github.com/Daveedick/iphone-app-transfer) · [Prerelease v0.1.4](https://github.com/Daveedick/iphone-app-transfer/releases/tag/v0.1.4). Тег относится к проверенному source commit `7f444465150b0e33d4c5daddbb3a071dc3ae68b2`; последующие изменения отчётов не меняют runtime inputs.

Полный GUI install/readback/launch на втором телефоне, live второй аккаунт, iOS 27, чистый Mac и downloaded/quarantined Gatekeeper-flow остаются pending. Лицензия собственного кода пока не выбрана; public visibility требует отдельного решения.

## Реализация

- [x] SwiftPM native app: SwiftUI/AppKit, arm64, macOS 15+, реальное окно запускается.
- [x] Pinned ipatool 2.7.0 / `4484b55d366e177ae6c89758c61588712c572fad`; отдельный JSON-lines Go helper, без разбора CLI-подсказок.
- [x] Прямой C-мост: USB/hotplug, сведения, app metadata, offloaded, иконки, AFC upload, terminal install status, readback API.
- [x] GUI формы Apple Account/2FA, отдельные Keychain/cookies, безопасные ошибки и отмена; **живой GUI login и download подтверждены**.
- [x] Проверка IPA: полный проход ZIP/CRC, безопасные пути, bundle/version/build, SHA-256, metadata/SINF presence; собственная persistent библиотека.
- [x] Download-only / transfer / install-library, последовательный coordinator, immutable destination, pause/cancel, recovery и явный выбор альтернативной версии.
- [x] Multi-device workspace, скрываемая библиотека/очередь, журнал, поиск и multi-select, drag/drop и действия без перетаскивания.
- [x] Удаление из библиотеки в Trash с подтверждением и защитой файлов очереди; импорт копирует оригинал.
- [x] RU/EN, компактная/свободная плотность, system/light/dark, persistent preferences; outside/Escape/deactivation dismissal.
- [x] Самостоятельный release `.app` с embedded helper и шестью dylib; ad-hoc signing и dependency verification.
- [x] Финальный DMG, read-only mount/relocated copy, source-digest verification и SHA-256.
- [x] Свежий GUI login → metadata → Craftersy 5.1 download → validated library; после перезапуска всё сохранено.
- [ ] Install/readback → запуск приложения на втором iPhone; отдельное наблюдение реального OTP recovery.
- [ ] Clean-user / clean-Mac, quarantine Gatekeeper-flow, live iOS 27 и несколько живых аккаунтов.
- [x] Device uninstall сознательно deferred: C API есть, пользовательского действия в UI нет.

## Подтверждённые результаты

### Среда и сборка — local/native

macOS 15.6.1 arm64; Swift 6.0.3 CLT; Go 1.26.0. Full Xcode/XCTest отсутствуют. В CLT обнаружены несовместимые public/private PackageDescription interfaces и дублированный SwiftBridging module map. `scripts/swiftpm.sh` использует проектную копию matching manifest interfaces и VFS overlay; системные файлы и настройки защиты не менялись.

Debug и release native build проходят. `.app` запускается через Launch Services и показывает реальные данные. У восьми Mach-O (main/helper/6 dylib) проверены arm64, minimum OS и bundle-relative/system-only runtime paths. `codesign --verify --deep --strict` проходит. Это подтверждает packaging integrity, но не чистый Mac и не notarization.

### Устройство — live read-only

Bundled diagnostics и нативный UI прочитали iPhone 16 Pro Max / iOS 18.5: **333 приложения, 27 offloaded, 333 с store metadata**. Проверены иконка, bundle readback, subscribe/unsubscribe; тестовая программа C-моста не содержит вызываемых install/uninstall действий. iMazing, CSV, старые credential caches не использовались.

Пользователь подтвердил, что iPhone 17 сейчас недоступен. Новые install/uninstall на реальном iPhone не выполнялись. Предыдущие CLI-переносы из разговора не закрывают эту проверку нашего приложения.

### Helper — synthetic/native Keychain

11 Go contract tests проходят с race detector; `go vet` проходит. Проверены account isolation, отсутствие пароля в persisted upstream account, OTP/cancel boundaries и output path safety. Opt-in native Keychain create/read/update/delete прошёл на отдельной синтетической записи и удалил только её. `hello` и `account.list` выполняются из packaged helper; namespace приложения изначально пустой.

Пользователь завершил настоящий вход в GUI. Затем из реального списка скачан Craftersy 5.1, ~498 МБ; bundle/build/SINF и независимый SHA-256 подтверждены, Staging очищен. После финального relaunch аккаунт, библиотека и задача сохранились. Отдельный live экран/ошибка OTP агентом не наблюдался.

### Интерфейс — native

Через CUA проверены реальный список/иконки, переключение RU/EN, light/dark, немедленное применение настроек, Escape и скрытие библиотеки `⌘S`. После финального build подтверждены одно View menu, отдельные AX-кнопки строк, пустая queue Pause disabled и сохранение preferences. Сохранены native synthetic screenshots трёх устройств (light/dark) и пяти с overflow в docs/screenshots. Ручной pointer drop пользователя подтвердился второй completed задачей с тем же library ID и одним сохранённым IPA. CUA mouse transport отдельно не подтвердился и не считается отрицательным доказательством ручного DnD. Дополнительно exact UTF-8 provider/JSON roundtrip проверен исполняемым probe. Остальные направления/edge DnD pending.

### Domain tests

Core/Coordinator: portable CLT runner с теми же test bodies прошёл 18 тестов, 86 assertions, 0 failures; negative self-check подтверждает exit 1 при ошибке assertion/async teardown. Это не запуск XCTest. Отдельные C safety tests проходят под ASan/UBSan; живые чтения проходят только с явным `--live-read-only`.

## Осталось перед передачей

Готовы `.app` и `.dmg`; build integrity, исходники и все доступные локальные/live read-only/download проверки сведены в `docs/QA.md`. Ручной phone→library drop и reuse подтверждены; остаются недоступные проверки второго телефона/clean Mac. Установка не объявляется проверенной до iPhone 17.

DMG SHA-256: `07fca0c3c645955f989c55f734c624e184c9c1bbdb1480452e3b984c5a1b6731`.

Source digest: `648dda6970a6fc56231d37936d58da44d0e4eadcdfbf9b0c7cdb2d2a81daddad`.

Команды: [scripts/README.md](scripts/README.md). Пользовательская инструкция: [README.md](README.md). Пароли, OTP, email/UDID, IPA и raw phone inventory в этот отчёт не включаются.

## 19.10.2026 — 0.1.1: оформление обновлено и проверено

Пользователь утвердил план визуальной доработки по присланным скриншотам Raycast и разрешил реализацию. Уточнённые правила закреплены в `DESIGN.md` и имеют приоритет над визуальными деталями сохранённых прототипов. Библиотека, равноправные колонки устройств, очередь и утверждённые сценарии переноса сохраняются.

Доработка охватывает нейтральное выделение строк без зелёной рамки, отдельный аккуратный клавиатурный фокус, удаление постоянных галочек готовых IPA, сокращение обводок, спокойные инструменты и поиск, согласованные отступы/типографику, приглушённое стекло, компактные панели выбора/очереди и более тихие настройки/аккаунты. Анимации обычных кнопок меняют заливку без масштабирования.

В финальной сборке подтверждён один iPhone 16 Pro Max / iOS 18.5, 333 приложения, один сохранённый аккаунт и один IPA. Установки и удаления на телефоне не выполнялись. Второй телефон по-прежнему недоступен для live установки.

- [x] Последние требования пользователя внесены в дизайн-документ.
- [x] Обновлены нативные списки, панели, настройки и аккаунты; release `.app` 0.1.1 (2) собран.
- [x] GUI: обе темы/плотности, RU/EN, нейтральное выделение, Tab и фокус, Command-клик и Shift-диапазон, поиск/пустой результат, ⌘S/⌘J, Escape и outside click. Исправлено чтение модификаторов выделения из текущего события.
- [x] Live read-only: 333 приложения на подключённом iPhone; сохранённые аккаунт/библиотека/очередь пережили перезапуск.
- [x] Native synthetic: три устройства dark/RU и light/EN; пять устройств в узком 920 × 680 pt окне. Кадры `docs/screenshots/raycast-*.png`.
- [x] Через «В библиотеку» создана ещё одна succeeded-задача Craftersy: три его завершённые задачи ссылаются на один IPA, Staging пуст. Подтверждение удаления открыто и отменено; файл сохранён.
- [ ] Две автоматические pointer DnD попытки остались inconclusive: они не доказывают успешный drop. Реальный ручной drop ранее подтверждён для 0.1.0; свежий manual drop и направления установки требуют отдельной проверки.
- [x] Release build, native GUI smoke, strict ad-hoc signatures, 8 Mach-O / 6 dylib dependency closure, DMG CRC/read-only mount/Applications link, relocated diagnostics и совпадение source digest. Подробности в `docs/QA.md`.

Предыдущие Core/helper/C safety/Trash результаты и SHA-256 выше относятся к preview 0.1.0. Доменная логика и helper не изменялись; эти suites повторно ради визуальных правок не запускались. Свежие GUI/packaging отчёты: `.build/qa/visual-refinement/gui-checks.json`, `.build/packaging-verification/visual-refinement-0.1.1.json`.

DMG 0.1.1: `dist/App-Transfer-0.1.1-arm64.dmg`, SHA-256 `228aff9de870e5004c94af0618d79e6be113954823c1e42e6542bd9aeb77a48b`; source digest `7ffaee947032b0098e8ea42dad845f5c139391759fc33448a477d09babf40516`. Live install/readback на втором iPhone, iOS 27, clean-user/clean-Mac и quarantine Gatekeeper-flow остаются открытыми.


## 19.10.2026 — 0.1.2: очередь по высоте, новые задачи сверху, отклик

- [x] Верхний разделитель очереди тянется мышью; курсор и grip обозначают изменение размера. Высота сохраняется, есть клавиатурная/AX adjustment альтернатива. Native drag: 312 → 462 pt; после перезапуска 462 pt.
- [x] Новые задачи и явные повторы сверху. Legacy JSON совместим; сортировка UI отделена от FIFO worker. Обновления прогресса/завершения не меняют положение строк.
- [x] Подтверждение, подсветка и scroll-to-task при принятом добавлении. Live: прокрутка старого списка 0.97196 → 0 после нового Craftersy; свёрнутая панель показывает «Добавлено: Craftersy» и не раскрывается сама. Pending duplicate возвращает существующий ID и понятный ответ.
- [x] Portable Core: 22 теста, 115 assertions, 0 failures; enqueue outcomes, equal dates/legacy decode, retry recency/persistence, FIFO и отсутствие перестановок на progress/completion.
- [x] Реальные данные сохранены: один аккаунт, восемь IPA, 333 приложения. Три live smoke-действия повторно использовали Craftersy, одна archive reference; библиотека осталась из восьми IPA, Staging пуст. На телефоне ничего не устанавливалось/удалялось.
- [x] Native demo minimum 760 × 560 pt после единственного correction pass сохраняет строку библиотеки; высота очереди ограничивается текущим окном и плотностью.
- [x] Release app/DMG 0.1.2 (3), strict ad-hoc signatures, 8 Mach-O / 6 dylib closure, CRC, mount и relocated read-only diagnostics прошли. Финальная app открыта в RU/dark/compact, очередь раскрыта на сохранённой высоте.

Финальный DMG: `dist/App-Transfer-0.1.2-arm64.dmg` (23 568 716 bytes), SHA-256 `10de5408cc5f961b6d94b1e91ae8d757ad60304b46b1f68d1016708ec341438e`. Runtime source digest: `3ef6c7497cd1e14a870ff8257038a6806f152758cd98fc236636d8c36e5e59bc`. Отчёты: `.build/qa/queue-update/gui-checks.json`, `.build/packaging-verification/queue-0.1.2.json`.

Прежние ограничения live install/readback на втором телефоне, iOS 27, clean Mac/quarantine и полной VoiceOver/system-accessibility проверки сохраняются. Ошибки прежних задач не скрывались и не запускались повторно автоматически.


## 19.10.2026 — 0.1.3: широкая полоса изменения высоты

- [x] Полоса захвата увеличена с 10 до 20 pt на всю ширину. Маркер 40 × 3 pt заметнее при наведении/фокусе; визуальный разделитель остаётся тонким.
- [x] Курсор обслуживается native AppKit tracking area / cursorUpdate и cursor rect; перетаскивание — native mouse events со стабильной экранной точкой отсчёта. Разовые SwiftUI onHover cursor overrides удалены.
- [x] GUI мышью: верхний край слева, вдали от маркера, 302 → 382 pt; нижний край справа 382 → 322 pt; клавиша ↑ → 346 pt; возвращено исходное 302 pt. Collapse/reopen и relaunch сохранили 302 pt, один аккаунт и восемь IPA. Активных задач нет, телефон при этой проверке не определялся; phone writes и новые transfer-задачи не выполнялись.
- [x] Native synthetic 760 × 560 pt, light/EN: видна строка библиотеки и очередь; новая полоса учтена в ограничении высоты.
- [x] Release build, strict ad-hoc signature, 8 Mach-O / 6 dylib closure, DMG CRC/read-only mount/Applications link/readme, relocated diagnostics и source digest прошли. App оставлена открытой.

CUA не предоставляет hover-only movement или отдельное чтение формы системного курсора: отсутствие визуального мерцания не измерено автоматически. Нативное владение курсором проверено по реализации, обработка drag и keyboard — через реальный GUI. Core/helper suites не запускались повторно для этого UI-исправления; результаты 0.1.2 сохраняют дату и область проверки.

DMG `dist/App-Transfer-0.1.3-arm64.dmg`, 23 562 813 bytes, SHA-256 `28bd49cef6f2c80018b549c9402b67fd766715f5967d7f81fdecc46f38c4a2fd`. Runtime source SHA `c1320bf7f0fc099197cb8dfa278032391e16af947329e8220fc2dd22aa9269a4`. Отчёты без секретов: `.build/qa/resize-hitarea/gui-checks.json`, `.build/packaging-verification/resize-hitarea-0.1.3.json`. Второй iPhone/install/readback, iOS 27 и clean Mac/Gatekeeper остаются вне этой проверки.
