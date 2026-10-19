# Техническая основа и подтверждённые факты

Сводка создана 19.10.2026 по экспериментам этого разговора. Это evidence исходного исследования iPhone App Transfer, а не обещание поддержки любой версии iOS или текущего состояния Apple servers. Дальнейшие результаты GUI и упаковки находятся в `../docs/QA.md` и `../STATUS.md`; исторический эксперимент ниже не заменяет актуальную приёмку.

## Что проверено напрямую

На подключённом iPhone 16 Pro Max с iOS 18.5 выполнен read-only вызов `installation_proxy` из собственного C-кода через libimobiledevice. iMazing, его CSV и cache не были входными данными этого эксперимента.

Ключ: явно запросить `iTunesMetadata`. Обычный краткий вывод списка приложений этих данных не показывает. Для offloaded/placeholder приложений нужен `ShowPlaceholders=true`; в эксперименте использован `instproxy_lookup`.

Параметры:

```text
ApplicationType = User
ShowPlaceholders = true
ReturnAttributes =
  CFBundleIdentifier, CFBundleDisplayName, CFBundleShortVersionString,
  CFBundleVersion, IsDemotedApp, ApplicationType, iTunesMetadata
```

Результат: 333 записи, из них 306 установленных и 27 offloaded. У всех 333 был store item ID; обычный external version ID — у 332; email аккаунта — у 329. Исключение с TestFlight имело beta version identifier вместо обычного App Store version ID. Не делать вывод «поле всегда присутствует» из одной выборки.

Вложенный iTunesMetadata содержит:

| Значение | Поле |
| --- | --- |
| Store item ID | `itemId` |
| Exact external version ID | `softwareVersionExternalIdentifier` |
| Bundle ID | `softwareVersionBundleId` |
| Display version | `bundleShortVersionString` |
| Build | `bundleVersion` |
| Подсказка об аккаунте | `com.apple.iTunesStore.downloadInfo.accountInfo.AppleID` |

Для offloaded приложения верхняя версия может отсутствовать; fallback из iTunesMetadata сработал. Account metadata также содержит другие идентификаторы — не переносить сырые объекты в UI/logs.

## App Store-проверки на свежих метаданных

| Приложение | Результат |
| --- | --- |
| Craftersy 5.1 | Свежий IPA успешно скачан; проверены ZIP CRC, bundle ID `apps.homepreserves.prohome`, версия/build и наличие SINF |
| Mail App 15.68.1 | `get-version-metadata` успешно вернул нужную версию; полного скачивания в этом эксперименте не было |
| Online 16.0.0 | Метаданные считаны с телефона, Apple ответила `license is required` |

Скачивание Craftersy использовало имеющуюся ipatool-авторизацию. Поэтому оно не доказывает новый GUI login, работу с чистым Keychain, новый Mac или отсутствие дополнительных first-run assets.

В предыдущих шагах разговора CLI-установка скачанных IPA на iPhone 17 Pro Max уже выполнялась, а Avito пользователь смог открыть. Однако установка через наш новый C-мост/GUI не проверена; в последнем read-only эксперименте целевого телефона не было. Не подменять эти разные уровни проверки.

## Артефакты в этой папке

- [device_metadata_probe.c](evidence/device_metadata_probe.c) — минимальный read-only пример. Пишет выходной plist с правами 0600 и `O_EXCL`, не содержит install/uninstall вызовов.
- Локальный `evidence/metadata-findings.json` исключён из Git и не входит в поставку исходников. Публичная сводка полей и агрегированных результатов приведена выше; для повторения используйте исходник probe и сохраняйте его вывод вне репозитория.

Пример компиляции эксперимента в среде разработчика, где библиотеки уже стоят через Homebrew:

```sh
clang -Wall -Wextra -I/opt/homebrew/include -L/opt/homebrew/lib \
  -Wl,-rpath,/opt/homebrew/lib research/evidence/device_metadata_probe.c \
  -limobiledevice-1.0 -lplist-2.0 -o /tmp/app-transfer-metadata-probe
```

Использование: `app-transfer-metadata-probe UDID OUTPUT_PLIST 1`. Результат содержит приватные метаданные: сохранять вне репозитория. Эти `/opt/homebrew` пути — только для повторения research probe, их нельзя переносить в релизный bundle.

## Текущие инструменты и ограничения

- Проверенный CLI-путь использовал ipatool 2.7.0 macOS arm64, ideviceinstaller 1.2.0_1, libimobiledevice 1.4.0_1. Перед реализацией сверить установленные версии и upstream provenance.
- Локально изученный `~/Downloads/ipatool-main` — ZIP checkout без Git metadata. В нём `go.mod` требует Go 1.26.5 и имеет local replacement `github.com/blacktop/lzfse-cgo => ./internal/lzfsecompat`. Версия папки не доказана как release 2.7.0.
- Core API имеет injectable Keychain/CookieJar; это полезно для собственного namespace. В логике Login исходника account может содержать Password и PasswordToken: не сериализовать такой объект в diagnostics/GUI events.
- SAP signer подготавливает дополнительные assets/runtime. Проверить first-run network/cache/licensing прежде, чем обещать полностью самостоятельную упаковку.
- Активный toolchain этого Mac: Swift 6.0.3 на CLT, target arm64-apple-macosx15.0. `xcodebuild` сейчас не использует полный Xcode. Это обнаруженное состояние, не вечное ограничение проекта.
- `instproxy_install` и `instproxy_uninstall` присутствуют в локальном заголовке библиотеки. Uninstall — технически доступная возможность; безопасная продуктовая реализация и live test ещё не проведены.

## Чего не считать доказанным

1. Live metadata read на iOS 27 через наш C-мост.
2. Полный свежий login/2FA в GUI и изоляция нескольких Apple Account.
3. Download entitlement только на основании установленных приложений.
4. Установка или запуск произвольного удалённого из магазина приложения.
5. Возможность работать без доступа к аккаунту, под которым приложение поставили в банке.
6. Самостоятельная clean-Mac сборка без Homebrew, старых auth caches и first-run runtime.
7. Корректный uninstall пользовательского приложения и сохранность unrelated данных.
8. Перенос локальных данных/банковских сессий: эта функция явно исключена из продукта.

## Первичные источники

- [ipatool, upstream](https://github.com/majd/ipatool), [core package](https://github.com/majd/ipatool/tree/main/pkg/appstore), [2.7.0 release](https://github.com/majd/ipatool/releases/tag/v2.7.0).
- [libimobiledevice](https://github.com/libimobiledevice/libimobiledevice), [installation_proxy API](https://github.com/libimobiledevice/libimobiledevice/blob/master/include/libimobiledevice/installation_proxy.h).
- [ideviceinstaller source: staging/install/uninstall](https://github.com/libimobiledevice/ideviceinstaller/blob/master/src/ideviceinstaller.c).
- [pymobiledevice3 installation proxy: ShowPlaceholders/Lookup reference](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/installation_proxy.py).
- [Apple: NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview), [materials](https://developer.apple.com/design/human-interface-guidelines/materials), [motion](https://developer.apple.com/design/human-interface-guidelines/motion).
- [Apple: macOS 27 AppKit design updates](https://developer.apple.com/videos/play/wwdc2026/289/), [concentric design system](https://developer.apple.com/videos/play/wwdc2025/356/).
- [Apple: transient popover](https://developer.apple.com/documentation/appkit/nspopover/behavior-swift.enum/transient). Transient закрывается при внешнем взаимодействии, но конкретные исключения включают некоторые меню/panels; проверить app-deactivation отдельно.
- [Apple: move files to Trash](https://developer.apple.com/documentation/appkit/nsworkspace/recycle(_:completionhandler:)).
- [Apple: opening software from unidentified developers](https://support.apple.com/en-us/102445).

Источники с `main/master` меняются. Исполнитель обязан зафиксировать revision используемого кода и записать результаты именно своей сборки.
