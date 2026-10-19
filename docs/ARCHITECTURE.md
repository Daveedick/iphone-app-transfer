# Архитектура iPhone App Transfer

Нативный MVP уже реализован. Ниже его основа и контракты; фактическая проверенность отдельных сценариев указана в [QA](QA.md) и [STATUS](../STATUS.md). Менять её можно только по результатам конкретного технического ограничения, сохраняя утверждённый продукт.

## Компоненты

```text
iPhone App Transfer.app
├── SwiftUI + узкие AppKit-адаптеры
│   ├── Workspace / Library / DeviceColumn / Queue / Activity
│   ├── Settings / App Store Accounts / Authentication
│   └── View models на MainActor
├── TransferCoordinator (actor): единственная очередь операций
├── DeviceService (serial DispatchQueue) → C bridge → libimobiledevice + libplist + зависимости
├── AppStoreService (actor) → Process + pipes → AppStoreBridge (Go)
│                                            └── pinned ipatool/pkg/appstore
├── LibraryStore: файлы IPA + атомарный versioned JSON manifest
├── OperationStore: версия схемы, очередь, локальный журнал
└── UserDefaults: тема, язык, плотность, видимость панелей
```

Не нужны web server, Electron, отдельный daemon, отдельный frontend framework, XPC-сервис или собственная реализация протокола App Store с нуля. SwiftUI напрямую использует тонкий C-мост; отдельный Go-процесс нужен из-за существующего ядра ipatool и изоляции его auth/runtime.

## Сборка

Сборка использует Swift Package Manager, executable target для приложения, C target/модуль для моста, тестовый target и отдельный Go helper. Скрипт собирает `.app` с Info.plist, ресурсами и зависимостями, затем DMG через системные инструменты. Xcode может открывать package, но не становится пользовательской runtime-зависимостью.

Текущий Mac: macOS 15.6.1, arm64; активны CLT и Swift 6.0.3. `xcodebuild -version` сейчас сообщает, что активный developer directory — CommandLineTools. Сначала проверить, чего действительно хватает для сборки и локализации. Если нужен полный Xcode/другая версия SDK, указать точную причину и продолжать независимые задачи; не делать обновление системы скрытым шагом.

Текущая структура исходников:

```text
Package.swift
Sources/AppTransfer/{main.swift,WorkspaceView.swift,AppModel.swift,Resources,...}
Sources/AppTransferCore/{Models,Stores,IPAInspector,TransferCoordinator,QueuePresentation}.swift
Sources/DeviceBridge/{include,device_bridge.c}
Helpers/AppStoreBridge/{go.mod,cmd,internal,upstream/ipatool}
Tests/{AppTransferCoreTests,PortableRunner,PortableTestSupport}
scripts/{bootstrap-deps,build-app,package-dmg,verify-bundle}.sh
vendor/manifest.json
THIRD_PARTY_NOTICES.md
```

Прототипы не должны оказаться встроенным WebView-интерфейсом. Они остаются design reference.

## Работа с устройствами

1. Обнаруживать USB-устройства и подписываться на подключения/отключения. Отдельно проверить initial enumeration и hotplug.
2. Для каждого устройства использовать UDID, независимое состояние pairing/trust/lockdown и собственные подключения к сервисам. Не хранить глобальный mutable «текущий телефон».
3. Список: `installation_proxy` Lookup с `ApplicationType=User`, `ShowPlaceholders=true` и явным `ReturnAttributes`, включая `iTunesMetadata`.
4. `iTunesMetadata` может быть вложенным plist в data-значении. Разбирать безопасно, проверять типы, отсутствие полей и альтернативный источник версии для offloaded apps.
5. Иконки получать доступным device API или из IPA. Ошибка иконки не блокирует список. Запросы и кэш ограничены по числу, выполняются вне UI-потока.
6. Установка: использовать поддерживаемый путь загрузки IPA на устройство (AFC staging) и `instproxy_install`; изучить текущий `ideviceinstaller` как reference. Освобождать временный staging по фактическому состоянию операции.
7. Успех — callback/terminal status + независимый Lookup bundle/version на том же UDID. Возврат success из async-start ещё не означает завершение установки.
8. Не вызывать uninstall перед install как «исправление». Не делать restore/erase/re-pair без необходимости и разрешения.
9. Опциональное удаление — `instproxy_uninstall`, подтверждённое readback. Никогда не путать его с `instproxy_remove_archive`.

C-мост должен скрывать ручное управление памятью и приведение типов, не включать бизнес-логику. Блокирующие C-вызовы выполняются на выделенной serial queue/executor, не на MainActor и не просто внутри actor, блокируя cooperative thread pool. Определить владельца callback context, lifetime и cleanup при disconnect.

## App Store helper

Использовать `ipatool/pkg/appstore`, а не парсить CLI-подсказки. В исследованном исходнике есть Login, AccountInfo, Download, ListVersions, GetVersionMetadata и внедряемые Keychain/CookieJar. Сам публичный пакет не считать стабильным API: зафиксировать tested tag/commit и обернуть своим небольшим контрактом.

Helper использует официальный Go module archive ipatool v2.7.0, commit `4484b55d366e177ae6c89758c61588712c572fad`, сохранённый в `Helpers/AppStoreBridge/upstream/ipatool`; local `replace` указывает на этот каталог. Папка `Downloads/ipatool-main` не является входом текущей сборки. Сохранённый patch меняет только runtime-cache namespace и не переписывает Apple-протокол; provenance и checksums описаны в `Helpers/AppStoreBridge/UPSTREAM.md` и `vendor/manifest.json`.

При недоступности исходной версии UI может предложить только полученный от Apple актуальный candidate, с явным подтверждением; произвольного исторического version picker нет. Порядок выбора аккаунта: вошедший owner-matching account → вошедший аккаунт по умолчанию → единственный доступный; owner metadata не доказывает entitlement, явный выбор задачи имеет приоритет. Общий resolver возвращает аккаунт и причину, чтобы preview выбора и создание задачи совпадали. После enqueue аккаунт задачи не меняется при переключении общего default.

Пояснения 0.1.5 не меняют Apple helper или IPC-протокол. UI разделяет аккаунт скачивания, account hint исходного телефона и сведения самого IPA. Для импортированного/старого IPA без подтверждённого downloader нельзя выводить «Скачано через» только на основании email в metadata. Задача и Activity сохраняют необязательный снимок фактически использованного IPA с известными связями аккаунта. Если источник связан с A, а скачивание и IPA — с B, возможный аккаунт для iPhone — B. Конфликт downloader/IPA metadata показывается как неопределённость; установка и успешный запуск остаются разными состояниями.

### IPC

Один дочерний helper, JSON Lines через stdin/stdout. Протокол версионирован, у каждой команды `requestId`, у события — `requestId`/`operationId`. stdout содержит только события протокола, stderr — только очищенную диагностику. Не запускать shell для команд приложения.

Команды текущего контракта: `hello`, `account.list`, `auth.begin`, `auth.submitCode`, `auth.cancel`, `account.remove`, `app.versionInfo`, `app.versions`, `app.download`, `operation.cancel`. События: `ready`, `auth.preparing`, `auth.codeRequired`, `auth.succeeded`, `download.progress`, `completed`, `failed`, `canceled`.

Это контракт нашего adapter; upstream может иметь другую форму auth-вызовов. Adapter хранит нужное промежуточное состояние, чтобы GUI получал явный запрос 2FA и не вводил секреты повторно без причины.

Пароль/OTP передаются только через закрытый pipe, не через argv, URL, env, временный файл или лог. Разделять framing сообщений и данные пользовательского ввода; задавать верхние границы размера сообщений и типизированные ошибки. При падении helper UI получает ошибку/состояние восстановления, не зависает.

### Изоляция аккаунтов

- Локальная библиотека и snapshot очереди показываются до завершения чтения реестра аккаунтов. Ожидание системного Keychain не должно выглядеть как пустая библиотека; аккаунты в это время имеют явное состояние загрузки.
- Внутренний UUID аккаунта не равен строке email. Смена display email не подменяет license owner.
- Keychain service `com.apptransfer.AppStoreBridge.v1` принадлежит только iPhone App Transfer; не использовать существующие `~/.ipatool` и глобальную запись `account` другого процесса.
- На каждый аккаунт отдельные credentials/cookies/storefront; нельзя делить mutable cookie jar между аккаунтами.
- Keychain-адаптер возвращает только секреты выбранного account ID. Сохраняются session credentials; пароль и OTP используются временно при входе и не сохраняются. Истечение сессии требует повторного GUI login, автоматическое password refresh не заявлено.
- Cookies могут быть токенами авторизации: они хранятся в Keychain, не в открытом JSON рядом с IPA.
- Не считывать старые сессии iMazing/ipatool автоматически. Отдельная проверка нового пользователя Mac обязательна.
- Первый login или download может подготавливать SAP assets/runtime. Проверить источники, кэш, сетевые загрузки, целостность и условия распространения; не копировать все найденные Apple binaries в публичный bundle вслепую.
- Удаление аккаунта явно удаляет его локальную авторизацию. Сохранённые IPA остаются с обозначенным владельцем лицензии, но запуск может всё равно требовать этот аккаунт. Повторное добавление того же email создаёт новый UUID и не перепривязывает существующие library/job references автоматически.

## Модели данных

| Модель | Обязательные данные |
| --- | --- |
| Device | UDID, display name, model, iOS, USB state, trust/lock state, optional free space |
| DeviceApp | device ID, bundle ID, name, display version/build, store item ID, external version ID, installed/offloaded state, metadata origin, optional account hint |
| AppleAccount | internal UUID, display email, storefront, auth state; секреты отдельно |
| LibraryItem | UUID, bundle/store ID, display/build/external version, account UUID/known owner, SHA-256, relative managed path, bytes, min iOS/device family if available, validation state |
| TransferJob | UUID, kind, immutable source/target IDs, requested version policy, resolved download account/reason, account/library references, optional actual-IPA account snapshot, stage, measured progress, timestamps, structured error |
| ActivityEntry | job ID, app/version, source/target snapshots, download account and actual-IPA account snapshot, result/stage/time; без raw auth |

Ключ совместимости библиотеки не должен быть только bundle ID или названием файла. Для повторного использования учитывать bundle ID + exact build/version ID + account/license provenance + подходящий вариант для устройства. Не объединять всё по маркетинговой версии.

## Хранение и удаление

Переименование 0.1.4 меняет видимый бренд и `.app`/DMG, сохраняя Bundle ID `app.apptransfer.desktop`, Keychain service `com.apptransfer.AppStoreBridge.v1`, UserDefaults suite `com.apptransfer.AppTransfer`, библиотеку `~/Library/Application Support/AppTransfer` и runtime-кэш `~/Library/Caches/App Transfer`. Миграция этих идентификаторов не выполняется. Реестр аккаунтов и email хранится в Keychain; локальные manifest/history могут отдельно содержать owner email и идентификаторы устройств.

Используются versioned Codable JSON manifests, атомарная запись через временный файл/rename и один actor-владелец. Данные приложения — в Application Support; реальные артефакты не в репозитории и не в `.app`. Для больших историй можно позже заменить storage без изменения domain API.

Новые сведения об аккаунте/IPA необязательны при декодировании: старые manifest/history читаются без переписывания IPA. Отсутствие подтверждённого downloader сохраняет неизвестное происхождение; удаление авторизации не стирает исторический снимок. Установка готового архива не требует новой авторизации на Mac только ради установки.

Архив сначала пишется в `.partial`, проходит проверку и только потом получает финальное имя и статус ready. На старте проверять missing files, незавершённые операции и временные файлы. Не считать переименование файла доказательством установки.

`deleteLibraryItems` проверяет references очереди, ограничивает пути managed root, перемещает файлы в Trash (`FileManager.trashItem`/`NSWorkspace.recycle`), после успеха обновляет manifest. При частичной ошибке сохранить оставшиеся записи и показать точный результат. Чужие импортированные originals не удалять: импорт копирует файл в managed storage.

## Проверка IPA

Проверяется целостность ZIP, безопасность путей, единственная основная `Payload/*.app/Info.plist` и метаданные. Для скачанного IPA bundle ID/версия/build сверяются с независимо ожидаемыми значениями, когда они известны. Импорт читает метаданные самого архива без независимого ожидаемого identity и не подтверждает его подлинность; `accountID` импортированной записи неизвестен. Проверка наличия SINF не доказывает действительность лицензии. Не распаковывать недоверенные пути через `../`/symlink вне рабочего каталога.

Несовместимый или неизвестный архив не показывать как заведомо устанавливаемый. Импорт без подтверждённого аккаунта явно помечается. Переподпись, извлечение DRM-ключей и исправление чужой лицензии вне scope.

## Состояния задач

```text
queued → resolving → [awaitingAccount / awaitingVersionChoice / awaitingDevice]
        → downloading → validating → cached
        → uploading → installing → verifyingDevice → succeeded
```

Для library-only после `cached` задача завершена. `skipped`, `failed`, `canceled`, `interrupted` — отдельные terminal/recovery состояния. Поле progress относится к текущей стадии, а не к произвольной линейной шкале всего переноса.

После перезапуска незавершённые активные задачи получают `interrupted`; пользователь запускает Retry, а целевой телефон проверяется снова. Нельзя воспроизводить `installing` автоматически или объявлять success без чтения устройства. Обычные queued-задачи могут продолжиться, если очередь не на паузе. После потери источника можно продолжать уже разрешённое скачивание по сохранённым метаданным; после потери назначения требуется тот же UDID.

## Упаковка и зависимости

- Библиотеки и их transitive dylib располагаются внутри bundle с корректными `@rpath`/`@loader_path`. Проверить `otool -L`, архитектуру и минимальную версию OS каждого бинарника.
- В production bundle не должно быть ссылок на `/opt/homebrew`, `/usr/local/Cellar`, каталог разработки или `Downloads/ipatool-main`.
- Swift runtime/системные frameworks использовать стандартно; Go toolchain не нужен на пользовательском Mac.
- Не поднимать свой usbmuxd daemon, пока не доказана необходимость. Для macOS использовать системное USB-подключение через поддерживаемый библиотекой механизм.
- Начальный desktop bundle распространяется вне App Store; App Sandbox не включать механически без проверки USB/helper/file access. Не заменять sandbox-настройки запросом root-доступа пользователю.
- Лицензии проверять по реально включаемым pinned файлам и transitive dependencies: ipatool — MIT, libimobiledevice tree содержит LGPL/GPL-компоненты. Не считать GPL CLI-код автоматически тем же, что лицензия библиотеки. Предпочтение динамической линковке, notices и воспроизводимым исходникам зависимостей.
- Подписывать ad-hoc вложенные исполняемые файлы/библиотеки, затем основной bundle; проверять целостность. Это не notarization и не обещание отсутствия Gatekeeper-предупреждения.


## Queue presentation (0.1.2)

`TransferJob.lastQueuedAt` is an optional persisted enqueue/retry date; legacy jobs use `created`. `QueuePresentation.newestFirst` sorts a UI copy with reverse insertion-order tie breaking. The coordinator's original array is unchanged: one ready job runs at a time in stored order. Retry changes visual recency without moving that execution position. Progress/completion update `updated` but never presentation recency. `enqueue` returns `EnqueueOutcome(jobID, inserted)` so pending duplicates receive honest feedback; `retry` returns acceptance.

`AppModel` applies a fresh snapshot after enqueue/retry and emits an ephemeral feedback token. `TransferQueuePanel` scrolls only for that token, highlights affected IDs and displays acknowledgment even when collapsed. Drag height is transient until release; `Preferences.queueBodyHeight` stores the desired height, while window-dependent clamping only affects rendering.
