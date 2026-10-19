# Проверка и публикация iPhone App Transfer 0.1.5 (6)

19.10.2026. Пользователь проверил локальную сборку и одобрил commit/push и prerelease. [v0.1.5](https://github.com/Daveedick/iphone-app-transfer/releases/tag/v0.1.5) опубликован с DMG/checksum; публичное скачивание и совпадение SHA-256 проверены. Одобрение интерфейса не заменяет pending live-проверки ниже.

- **Core/Coordinator:** 30 portable CLT tests, 176 assertions, 0 failures; negative harness self-check pass. Новые проверки охватывают owner-first/default/unresolved selection, source A → actual download/IPA B, импорт без Mac-account, metadata/download conflict, legacy JSON и snapshot истории после удаления синтетического IPA. Это не XCTest и не live install.
- **Native GUI:** synthetic RU/dark 1160 × 820 и EN/light 760 × 560, длинные email; AX readback account popover RU/EN, явной причины выбора, import/unknown/conflict, Activity с аккаунтом фактического IPA, обеих плотностей и свёрнутой очереди. Snapshot-host keyboard transport inconclusive; не выдаётся за полную проверку клавиатуры/VoiceOver.
- **Обычный запуск:** финальная `.app` показывает 10 существующих IPA и сохранённую очередь; manifest, operations и preferences имеют прежние SHA-256. Сохранены 20 задач и 24 события. Новые задачи/phone install/uninstall/login/download не выполнялись; USB-телефон отсутствует.
- **Keychain:** реальное чтение registry ожидает внутри `SecItemCopyMatching` (подтверждено коротким stack sample без данных авторизации). Startup теперь отображает библиотеку/очередь до завершения этого чтения; аккаунты имеют явное loading-состояние. Новый login, актуальность Apple-сессии и скачивание не проверены. Системные ACL/защита macOS не менялись.
- **Упаковка:** release `.app` 0.1.5 (6), strict ad-hoc signature, 8 Mach-O / 6 dylib closure, 37 Go module notices, исходный digest, DMG CRC/checksum, read-only mount, Applications symlink и relocated helper hello — pass. Helper/C не менялись; Go race/vet и C sanitizers повторно для этой правки не запускались.
- **Git:** действующая терминальная авторизация `Daveedick` подтверждена вне sandbox. Runtime commit `e06706cd0974d4b187c4370e2ffceeb18cf1397e` отправлен в публичный `main`; тег `v0.1.5` указывает на `7a5c202495b28035854c702ed134e7f9a75c7d9b` с документами поставки. Позднейшие изменения отчётов не меняют runtime inputs и тег.
- **Публикация:** GitHub API подтверждает `draft=false`, `prerelease=true`, публичный репозиторий и ровно два вложения — DMG (23661245 bytes) и checksum (102 bytes). Без credentials получены HTTP 200 для страницы/метаданных релиза, репозитория, тега и обоих файлов; SHA-256 скачанного DMG совпал, `shasum -c` — OK.
- **Свежий clone:** тег получен без credential helper и интерактивного входа; 329 tracked-файлов, commit и runtime digest совпали с проверенной сборкой. Сборка из этого clone повторно не выполнялась; это проверка доступности и комплектности исходников, не clean Mac.

DMG: `dist/iPhone-App-Transfer-0.1.5-arm64.dmg`, 23661245 bytes. SHA-256 `d4a49789ca23000074dc4450b57c4f3bbb446638bba4e43f1373d1078cd92e8b`. Runtime source SHA-256 `66ee5e9b8b0cd4fce35372ae67079bc1a10ef1cd3e2ea0c38abf6b1c608c8efc`.

Private ignored evidence: `.build/qa/accounts-0.1.5/core-results.log`, `build.json`, `packaging.json`, `preservation.json`, `git-access.json`, `publication.json`, `fresh-clone-release.json` и synthetic PNG. Clean Mac/Gatekeeper, live второй аккаунт/устройство/запуск и лицензия собственного кода остаются открытыми.

---

# Архив проверки preview 0.1.4 (5)

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

---

# Архив проверки preview 0.1.3 (4)

## 19.10.2026 — 0.1.3: широкая полоса изменения высоты

- [x] Полоса захвата увеличена с 10 до 20 pt на всю ширину. Маркер 40 × 3 pt заметнее при наведении/фокусе; визуальный разделитель остаётся тонким.
- [x] Курсор обслуживается native AppKit tracking area / cursorUpdate и cursor rect; перетаскивание — native mouse events со стабильной экранной точкой отсчёта. Разовые SwiftUI onHover cursor overrides удалены.
- [x] GUI мышью: верхний край слева, вдали от маркера, 302 → 382 pt; нижний край справа 382 → 322 pt; клавиша ↑ → 346 pt; возвращено исходное 302 pt. Collapse/reopen и relaunch сохранили 302 pt, один аккаунт и восемь IPA. Активных задач нет, телефон при этой проверке не определялся; phone writes и новые transfer-задачи не выполнялись.
- [x] Native synthetic 760 × 560 pt, light/EN: видна строка библиотеки и очередь; новая полоса учтена в ограничении высоты.
- [x] Release build, strict ad-hoc signature, 8 Mach-O / 6 dylib closure, DMG CRC/read-only mount/Applications link/readme, relocated diagnostics и source digest прошли. App оставлена открытой.

CUA не предоставляет hover-only movement или отдельное чтение формы системного курсора: отсутствие визуального мерцания не измерено автоматически. Нативное владение курсором проверено по реализации, обработка drag и keyboard — через реальный GUI. Core/helper suites не запускались повторно для этого UI-исправления; результаты 0.1.2 сохраняют дату и область проверки.

DMG `dist/App-Transfer-0.1.3-arm64.dmg`, 23 562 813 bytes, SHA-256 `28bd49cef6f2c80018b549c9402b67fd766715f5967d7f81fdecc46f38c4a2fd`. Runtime source SHA `c1320bf7f0fc099197cb8dfa278032391e16af947329e8220fc2dd22aa9269a4`. Отчёты без секретов: `.build/qa/resize-hitarea/gui-checks.json`, `.build/packaging-verification/resize-hitarea-0.1.3.json`. Второй iPhone/install/readback, iOS 27 и clean Mac/Gatekeeper остаются вне этой проверки.

[Native minimum-window fixture](screenshots/resize-hitarea-minimum-light.png).

---

# Архив проверки preview 0.1.2 (3)

19 октября 2026. Растягиваемая очередь, новые задачи сверху и явный отклик на добавление.

- **Core:** 22 portable теста, 115 assertions, 0 failures (`.build/portable-tests/results.log`). Новые проверки покрывают legacy decode даты, стабильные ties, accepted/duplicate outcome, сохранение retry recency, FIFO и отсутствие перестановки на progress/completion. Это CLT runner общих test bodies, не XCTest.
- **Native GUI:** drag верхнего разделителя 312 → 462 pt; после перезапуска — 462 pt. Старые и новые задачи отображаются newest-first. Управление высотой доступно также клавишами/AX actions; полная VoiceOver-проверка не заявляется.
- **Добавление:** из ранее прокрученной к старым задачам очереди (scrollbar 0.9719626) новый cache-only Craftersy вернул прокрутку к 0, появился первым с подсветкой и подтверждением. Свёрнутая панель показала «Добавлено: Craftersy», не раскрываясь. После раскрытия сохранены высота и новый порядок. Progress-only polling не создаёт feedback/scroll token.
- **Live read-only/cache:** iPhone 16 Pro Max / iOS 18.5 / 333 приложения, один аккаунт, восемь IPA. До проверки было 12 задач, после трёх reuse-действий — 15; три новых succeeded, архив Craftersy один, Staging пуст. На телефоне ничего не устанавливалось/удалялось. Старая failed-задача сохранена; автоматического retry нет.
- **Минимальное окно:** первый native synthetic pass выявил исчезновение строк библиотеки при высокой очереди. Исправлено ограничение высоты с учётом строки и плотности; финальный [кадр 760 × 560 pt, light/EN](screenshots/queue-minimum-light.png) показывает доступную строку библиотеки. Это synthetic demo, не реальные три телефона.
- **Упаковка:** release build, strict ad-hoc signature, 8 Mach-O / 6 dylib closure, arm64/macOS 15, DMG CRC/read-only mount/Applications link/readme, relocated copy и read-only diagnostics прошли. Source digest совпал с bundle. Собственный mount отключён.

Финальные файлы: `dist/App Transfer.app`, `dist/App-Transfer-0.1.2-arm64.dmg` (23 568 716 bytes). SHA-256: `10de5408cc5f961b6d94b1e91ae8d757ad60304b46b1f68d1016708ec341438e`. Runtime source: `3ef6c7497cd1e14a870ff8257038a6806f152758cd98fc236636d8c36e5e59bc`. Отчёты без email/UDID/secrets: ignored `.build/qa/queue-update/gui-checks.json`, `.build/packaging-verification/queue-0.1.2.json`. Первый кандидат DMG с хешем `947b…` superseded после исправления минимального окна.

Ранее перечисленные ограничения по второму iPhone/install/readback/launch, iOS 27, clean Mac/quarantine Gatekeeper и полной accessibility matrix остаются открытыми. Свежий live GUI login, сетевой download и новые направления DnD в рамках этого обновления не тестировались повторно.

---

# Архив проверки preview 0.1.1 (2)

19 октября 2026. Нативное оформление обновлено по утверждённым референсам Raycast. Сборка остаётся preview: установка на второй телефон, iOS 27, clean Mac и quarantine/Gatekeeper-flow требуют отдельной проверки.

## Свежие проверки 0.1.1

- Release build на Swift 6.0.3 CLT прошёл. Нативный рендер иконки выполнялся вне sandbox; системные SDK/настройки не менялись.
- Реальный GUI: iPhone 16 Pro Max / iOS 18.5, 333 приложения, один сохранённый аккаунт, один IPA. Перезапуск сохранил библиотеку, аккаунт, очередь и RU/dark/compact настройки.
- Проверены нейтральное выделение мышью, один тонкий контур клавиатурного фокуса, Tab, Command-клик и Shift+стрелка с двумя выбранными строками. Найденная гонка глобального состояния модификаторов исправлена: клавиатура читает `KeyPress.modifiers`, мышь — модификаторы текущего события.
- Проверены RU/EN, light/dark, compact/comfortable, независимый поиск и пустая выдача, скрытие/раскрытие библиотеки и очереди, Escape и закрытие аккаунтов кликом снаружи. Форма аккаунтов сохраняет SecureField; новые секреты не вводились. Изменения системных accessibility-настроек не выполнялись.
- Через «В библиотеку» повторно обработан Craftersy 5.1: новая задача completed, всего три его succeeded-задачи с одним library reference; в библиотеке один IPA, Staging пуст. Ничего на телефоне не устанавливалось и не удалялось.
- `⌘⌫` открыл подтверждение удаления только Craftersy; нажата «Отмена», IPA сохранён. Реальная Trash-операция отдельно проверялась ранее на fixture в 0.1.0.
- Две автоматические pointer drag попытки не создали задачу и считаются **inconclusive**. Работа кнопкой подтверждена; свежий manual drop не заявляется как пройденный. Установка на другой телефон не проверялась.

**Native synthetic**, тот же WorkspaceView с отдельным demo-хранилищем и отключёнными операциями с телефонами: [3 / dark RU](screenshots/raycast-three-dark.png), [3 / light EN](screenshots/raycast-three-light.png), [5 / narrow 920 × 680 pt](screenshots/raycast-five-narrow.png). Это не пять реальных подключённых устройств. GUI-отчёт с агрегатами без email/UDID/секретов: ignored `.build/qa/visual-refinement/gui-checks.json`.

## Поставка 0.1.1

`dist/App Transfer.app` и `dist/App-Transfer-0.1.1-arm64.dmg`. Проверены strict ad-hoc signatures, 8 Mach-O arm64/min macOS 15, шесть bundled dylib и отсутствие внешних developer-зависимостей, DMG CRC, read-only mount, Applications symlink/readme, подпись/зависимости перенесённой копии и её read-only diagnostics: один аккаунт и 333 приложения на iPhone 16. Собственный mount отключён. Это проверка relocation на текущем Mac, не clean-Mac тест.

DMG: **23 527 108 bytes**, SHA-256 `228aff9de870e5004c94af0618d79e6be113954823c1e42e6542bd9aeb77a48b`. Runtime source fingerprint совпал с embedded/mounted/relocated bundle: `7ffaee947032b0098e8ea42dad845f5c139391759fc33448a477d09babf40516`. Переносимый `.sha256` sidecar проверен. Отчёт: ignored `.build/packaging-verification/visual-refinement-0.1.1.json`.

Core/helper/C suites из отчёта ниже относятся к 0.1.0 и не запускались повторно для этих UI-изменений. Доменная логика, App Store helper, USB/install bridge и безопасное удаление IPA не изменены. Свежая проверка обработчиков выделения проведена через финальный GUI.

---

# Архив проверки preview 0.1.0 (1)

Дата: 19 октября 2026. macOS 15.6.1, Apple Silicon; Swift 6.0.3 CLT, Go 1.26.0. Это локальный preview, не полностью проверенный публичный релиз.

## Автоматические и локальные проверки

| Проверка | Результат | Доказательство |
| --- | --- | --- |
| Production Core + Archive / общий test source | 18 тестов, 86 assertions, 0 failures | `./scripts/test-core.sh`; ignored `.build/portable-tests/results.log` |
| Корректность переносимого runner | Intentional assertion + async teardown failure дают exit 1 | `.build/portable-tests/negative-self-check.log` |
| Стандартный XCTest | Не запускался: framework отсутствует в установленном CLT | На полном Xcode доступен `./scripts/swiftpm.sh test` |
| Helper contract / account isolation | 11 synthetic Go tests, `-race`, pass; `go vet` pass | `Helpers/AppStoreBridge/README.md` |
| Native Keychain | Create/read/update/delete отдельной синтетической записи pass | Opt-in helper self-test; реальный session content не читался |
| C bridge safety | ASan/UBSan pass; bounded ZIP/option handling и terminal status | `./scripts/test-device-bridge.sh` |
| Реальный IPA inspector | Avito 200.5 read-only, bundle/build/SINF и SHA совпали с независимым shasum | `.build/qa/native-library.json` |
| Реальный Trash API | Синтетический импорт → default FileManager trash → индекс пуст; исходник и точная Trash copy проверены | `.build/qa/native-library.json`; тестовая копия оставлена в Корзине |
| Runtime linkage/signature | Main, helper, 6 dylib: arm64, системные/bundle paths; deep/strict signature pass | scripts/verify-bundle.sh и packaging reports |

Включены проверки сохранения paused очереди после relaunch и чтения старого state без поля paused (safe default false).

Coordinator tests проверяют reuse одного скачивания между двумя targets, последовательность установки, download-only без install, account waiting с продолжением других задач, immutable destination после disconnect, crash recovery/readback, queued/before-binding deletion locks, staging cleanup при отмене, pause/cancel, отказ от false success без readback, missing-file detection и запрет late progress менять завершённый статус.

## Живое устройство и GUI

Подключён iPhone 16 Pro Max с iOS 18.5. Прямой C-мост и релизный bundle прочитали 333 пользовательских приложения, включая 27 offloaded. Подтверждены metadata, иконки и readback lookup, subscription cleanup. iMazing/CSV не являются входными данными.

Пользователь вошёл в Apple Account через форму App Transfer в новом Keychain namespace. В UI появился один авторизованный аккаунт. Затем через **В библиотеку** выполнено реальное скачивание **Craftersy 5.1** по метаданным телефона. IPA прошёл проверку, появился в библиотеке: около 498 МБ. Независимо проверены SHA-256, связь account reference с задачей, SINF и пустой Staging. Ни одна из этих операций не устанавливала и не удаляла приложения на iPhone.

Конкретный реальный экран OTP/повтор неверного кода агент отдельно не наблюдал: пользователь завершил вход сам. Это не заменяется утверждением, что live 2FA error recovery уже проверен. Synthetic helper tests покрывают протокол OTP/отмены.

Через стандартный open panel импортирован отдельный **App Transfer QA Fixture 1.0**. По `⌘⌫` показано подтверждение с именем только этой записи, затем файл удалён из библиотеки в Trash. UI вернулся к одному Craftersy, исходный fixture сохранился, авторизованный аккаунт остался. Пользовательские приложения для этого теста не удалялись.

На первом native UI pass проверены RU/EN, light/dark, immediate theme change, Escape и `⌘S`. Найденные проблемы дублированного меню View, AX-агрегации строк, hidden-library delete и Shift selection при фильтре исправлены. Финальный bundle перезапущен через Launch Services: остались один авторизованный аккаунт, Craftersy в библиотеке, выполненная задача и RU/light preferences; меню View одно, AX-строки отдельные, пустая очередь имеет disabled Pause. После последнего перезапуска сохранились обе completed задачи; пауза очереди теперь также persistent, migration старого state покрыта тестом.

Evidence `.build/qa/gui-smoke.json` содержит только агрегаты; email/UDID/session dumps в отчёт не включены.

## Поставка

Bundle содержит helper, библиотеки, icon, licenses, dependency manifest и source digest. `dist/App-Transfer-0.1.0-arm64.dmg` содержит App Transfer.app, ссылку Applications и Read Me. Read-only mount, signature/linkage checks и запуск diagnostics из перенесённой копии на этом Mac проверяются packaging script/agent. Это проверка relocation, а не доказательство чистого Mac.

Финальная проверка: 8 Mach-O / 6 bundled dylib, arm64/min macOS 15, deep/strict signatures, DMG CRC, read-only mount, Applications symlink/readme, relocated copy и запуск её diagnostics прошли. Diagnostics: 1 account, iPhone 16 / 333 apps / 27 offloaded, helper 2.7.0, deviceWrites=false. Смонтированный образ после проверки отключён.

DMG: 23 497 827 bytes, SHA-256 `07fca0c3c645955f989c55f734c624e184c9c1bbdb1480452e3b984c5a1b6731`. Source digest совпал между frozen sources и bundle: `648dda6970a6fc56231d37936d58da44d0e4eadcdfbf9b0c7cdb2d2a81daddad`. Машинный отчёт: ignored `.build/packaging-verification/final-qa.json`.

Сохранённые **native synthetic** состояния финальных view (не live телефоны): [3 / dark](screenshots/native-three-dark.png), [3 / light](screenshots/native-three-light.png), [5 / overflow](screenshots/native-five-overflow.png). Использован тот же WorkspaceView в отдельном explicit NSWindow harness с `--demo --snapshot`; production SwiftUI/auth branch не подменялся. Первые попытки автоматического snapshot до добавления этого harness не создавали окно и не считаются пройденными.

## Оставшиеся live-проверки

- iPhone 17 сейчас отсутствует — пользователь сообщил, что проверит позже. Полный download → AFC upload → installation_proxy → readback → открытие приложения через это приложение пока **не проверен**. Существующие приложения на iPhone 16 не использовались для destructive тестов.
- Реальный USB disconnect/crash во время установки, reconnect и запуск скачанного приложения.
- Второй живой Apple Account; реальный invalid OTP/session expiry recovery.
- iOS 27. Поддержка этой версии не выводится из успешного iOS 18.5 теста.
- Новый macOS профиль/другой Mac без Homebrew, iMazing, ipatool и auth/SAP caches.
- Quarantined/downloaded DMG, Gatekeeper Open Anyway и запуск из /Applications на чистой среде. Глобальная защита не отключалась.
- Телефон→телефон и библиотека→телефон pointer paths остаются pending до второго устройства. Phone→library пользователь выполнил вручную: в persisted state появилась вторая succeeded задача, ссылающаяся на тот же library ID; IPA остался один. Автоматические CUA drag-попытки были inconclusive. Exact UTF-8/plain-text provider acceptance и JSON roundtrip отдельно проверены native probe; в текущей сборке принимаются все три соответствующих text identifiers.
- Полный VoiceOver/системные Reduce Motion/Transparency/Increase Contrast и edge DnD до скрытого пятого устройства требуют ручной проверки. Код учитывает системные accessibility settings; это не заменяет empirical check.

Установка подтверждается только readback конкретного bundle/version. Даже после её успеха требуется отдельно открыть приложение на iPhone: Apple Account и обычный app login могут оставаться обязательными. Device uninstall отложен; перенос сессий и локальных данных исключён из scope.
