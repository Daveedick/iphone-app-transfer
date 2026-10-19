# GitHub CLI и публикация / GitHub CLI and delivery

Repository: [`Daveedick/iphone-app-transfer`](https://github.com/Daveedick/iphone-app-transfer). Product: **iPhone App Transfer**. The current delivery is **public**, including prerelease [`v0.1.5`](https://github.com/Daveedick/iphone-app-transfer/releases/tag/v0.1.5), build 6. The owner approved the local account-clarification update, source commit/push and publication of its verified DMG/checksum. Original-code license selection and live acceptance checks remain pending. Check actual repository/release state before repeating any creation command.

## Постоянный доступ к GitHub CLI

На Mac автора `gh` установлен, а вход под `Daveedick` ранее проверен. Для продолжения обычно достаточно:

```sh
gh api user --jq .login
gh auth setup-git --hostname github.com
```

Если первая команда возвращает ожидаемый логин, повторная авторизация и браузер не нужны. Учётная запись GitHub не связана с Apple Account, используемым внутри приложения.

Только при первой настройке другого Mac или фактической ошибке авторизации выполните:

```sh
gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git --hostname github.com
gh api user --jq .login
```

Подтвердите GitHub CLI в браузере своего Mac. Пароль, код 2FA и токен не пересылайте в чат, issue, `.env`, исходники или логи. Не используйте `gh auth token` для диагностики. GitHub CLI сохраняет учётные данные через доступное локальное хранилище; его авторизация и разрешения текущей среды выполнения — разные вещи. Если агенту нужен доступ к Keychain/сети за пределами sandbox, разрешение должно относиться к конкретной операции, а не к раскрытию токена.

## История: первый commit и private repository

Работать из корня проекта. Сначала проверить `git status`, текущую ветку, `git remote -v`, идентичность автора и состав staged changes. Если `origin` уже существует, сверить его адрес и удалённую историю; не выполнять force push, reset или повторное создание вслепую.

При подготовке первого коммита был предусмотрен контроль всего набора файлов, включая изображения; тот же контроль нужен для последующих изменений. `.gitignore` исключает `dist`, `.build`, IPA, личные дампы, секреты и private-логи. Приватность не заменяет этот контроль; теперь история репозитория тоже доступна публично. Vendored ipatool, патчи, lockfiles, notices и лицензии зависимостей нужны для сборки и должны остаться в исходниках. Лицензия собственного кода ещё не выбрана.

Следующие команды фиксируют первоначальный приватный этап и приведены как история. Репозиторий уже существует и открыт по последующему решению пользователя: не повторять `gh repo create --private` для текущей поставки.

```sh
git add .
git diff --cached --stat
git diff --cached --check
git commit -m 'Prepare iPhone App Transfer private preview'
gh repo create Daveedick/iphone-app-transfer \
  --private \
  --source=. \
  --remote=origin \
  --push
```

Пользователь уже разрешил текущую поставку и публичную видимость; повторный вопрос на каждый commit/push не нужен. При существующем репозитории применять обычные последующие commit/push после проверки remote.

Подтверждение результата:

```sh
gh repo view Daveedick/iphone-app-transfer --json nameWithOwner,isPrivate,visibility,url
git remote -v
git rev-parse HEAD
git ls-remote origin refs/heads/main
```

Текущее ожидаемое состояние: `isPrivate: false`, `visibility: PUBLIC` и одинаковый SHA локального `HEAD`/удалённого `main`. Описание и release notes не должны обещать завершённые проверки второго телефона, двух аккаунтов или чистого Mac.

## Если API работает, а Git push зависает

В первой отправке на Mac автора API GitHub работал, но HTTP-транспорт Git задержал завершение. Перед повтором проверьте удалённый SHA: коммит уже мог попасть на сервер. Помог однократный запуск с настройками только для команды:

```sh
git -c http.version=HTTP/1.1 \
  -c http.postBuffer=10485760 \
  -c http.lowSpeedLimit=1024 \
  -c http.lowSpeedTime=30 push -u origin main
```

Это не отключает TLS-проверку и не меняет глобальные настройки Git. Не запускайте повторную авторизацию, если `gh api user --jq .login` уже работает. В ограниченной среде HTTP 401 при чтении Keychain может требовать разрешённого запуска конкретной операции вне sandbox; токен выводить не нужно.

## Публично доступный preview-релиз

Сначала собрать и проверить `.app`/DMG по [инструкции сборки](../scripts/README.md). Изменение README не подтверждает существование рабочего DMG. Установка через GUI на второй телефон и чистый Mac остаётся pending до фактического теста.

### 0.1.5 (6): текущая публичная поставка

Пользователь явно одобрил публикацию этого prerelease после локального теста. Runtime inputs проверенного DMG соответствуют source commit `e06706cd0974d4b187c4370e2ffceeb18cf1397e`; тег может включать последующие изменения только документации. Runtime source digest: `66ee5e9b8b0cd4fce35372ae67079bc1a10ef1cd3e2ea0c38abf6b1c608c8efc`.

Проверенный DMG: `iPhone-App-Transfer-0.1.5-arm64.dmg`, 23 661 245 bytes, SHA-256 `d4a49789ca23000074dc4450b57c4f3bbb446638bba4e43f1373d1078cd92e8b`. Не менять опубликованные assets или tag вслепую. Сначала проверить существование v0.1.5 и его target/assets. Если тег/релиз отсутствуют и текущий коммит проверен:

```sh
git tag v0.1.5
git push origin v0.1.5
gh release create v0.1.5 \
  --repo Daveedick/iphone-app-transfer \
  --verify-tag \
  --prerelease \
  --title 'iPhone App Transfer 0.1.5 — preview' \
  --notes-file .build/qa/accounts-0.1.5/release-notes.md \
  dist/iPhone-App-Transfer-0.1.5-arm64.dmg \
  dist/iPhone-App-Transfer-0.1.5-arm64.dmg.sha256
git rev-list -n 1 v0.1.5
gh release view v0.1.5 --repo Daveedick/iphone-app-transfer
```

Release notes — подготовленный RU/EN файл, без секретов и личных данных. После публикации скачать оба assets в отдельный временный каталог, проверить sidecar через `shasum -a 256 -c iPhone-App-Transfer-0.1.5-arm64.dmg.sha256`, сверить размер/hash и подтвердить чтение без авторизации. Source digest DMG остаётся проверенным при изменениях только документации; новые runtime inputs требуют пересборки.

Выпуск проверен 30 portable Core-тестами / 176 assertions и native synthetic/packaging checks; полные результаты находятся в STATUS/QA. На текущем Mac системный Keychain-вызов блокирует чтение аккаунтов. Библиотека/очередь запускаются независимо, но новый живой login/download не подтверждён. Второй телефон/аккаунт, запуск, чистый Mac, downloaded-DMG/Gatekeeper и полная клавиатурная проверка остаются pending.

### История 19.10.2026: prerelease v0.1.4

Тег и release должны относиться к проверенному коммиту. Если `v0.1.4` уже существует, сравнить target и артефакты; не перемещать опубликованный тег и не заменять чужой файл вслепую. После подготовки release notes в обычном UTF-8 файле:

```sh
git tag v0.1.4
git push origin v0.1.4
gh release create v0.1.4 \
  --repo Daveedick/iphone-app-transfer \
  --verify-tag \
  --prerelease \
  --title 'iPhone App Transfer 0.1.4 — preview' \
  --notes-file /path/to/release-notes.md \
  dist/iPhone-App-Transfer-0.1.4-arm64.dmg \
  dist/iPhone-App-Transfer-0.1.4-arm64.dmg.sha256
```

`/path/to/release-notes.md` — явный placeholder: заменить реальным путём к подготовленному файлу. Release notes включают RU/EN описание, подтверждённые проверки, checksum и список pending. Видимость задаётся репозиторием; отметка prerelease сохраняет статус предварительного выпуска и не ограничивает публичное скачивание.

После публикации проверить `gh release view`, скачать оба файла в отдельный временный каталог и выполнить `shasum -a 256 -c iPhone-App-Transfer-0.1.4-arm64.dmg.sha256` из этого каталога. Отдельно клонировать репозиторий в новую папку и убедиться, что присутствуют исходники/helper/vendored core, а личные данные и сборочные артефакты отсутствуют. Свежий clone на том же Mac не заменяет установку на чистом Mac.

## Публичный доступ и оставшиеся проверки

Пользователь прямо разрешил открыть репозиторий сразу. Следующие задачи остаются открытыми и не означают, что public-доступ нужно снова согласовывать или откладывать:

1. Проверить полный GUI install/readback/launch на втором телефоне и работу с двумя Apple Account.
2. Проверить DMG, допустимый Gatekeeper-flow и первый login/download на Mac без Homebrew, Go, ipatool, старых сессий и runtime-кэшей.
3. Устранить обнаруженные ошибки и обновить обе инструкции/known limits по фактам.
4. Выбрать лицензию собственного кода с учётом состава зависимостей и обязательств по их исходникам/notices.
5. Повторно проверить всю Git-историю, release assets, изображения, issue templates и документацию на секреты и личные данные.
6. Подтвердить текущую PUBLIC-видимость и чтение репозитория/release assets без авторизации.

При обнаружении действующего секрета одного удаления файла из последнего коммита недостаточно: сначала отозвать секрет и отдельно обработать историю. Это не повод заранее публиковать чувствительные данные даже в private.

## English guide

GitHub CLI handles repository and release operations from Terminal; the browser is needed only for initial authorization or a later reauthorization. On the author's Mac, authentication as `Daveedick` has already been checked. Start with `gh api user --jq .login`; do not repeat `gh auth login` when that succeeds. `gh auth setup-git --hostname github.com` configures Git to use the CLI's credentials. Never print or share a token for troubleshooting.

The private-creation commands and dated `v0.1.4` example above record earlier delivery history and must not recreate or replace those published artifacts. The current release is `v0.1.5` (build 6); the owner explicitly authorized source and binary publication after local review. Inspect existing local/remote state before using the current commands. Review the staged tree for secrets, real phone inventories, IPA files and personal screenshots. Keep dependency source/patches/licenses needed by the bundled helper. Exclude `.build` and `dist`; upload the DMG and its checksum as release assets instead of Git source files.

If Git transport stalls while the CLI API succeeds, inspect the remote SHA before retrying; the scoped HTTP/1.1 command above does not weaken TLS verification or change global Git settings.

Verify `PUBLIC`, unauthenticated read access, the remote commit SHA, downloaded asset checksum and a fresh clone. None of these checks proves the second-phone installation or a clean-Mac first run. The owner has explicitly authorized public distribution now. Live testing and selection of a license for the original code remain pending; public visibility is not a completed acceptance test or an open-source license. A prerelease flag does not control repository visibility.

## Официальные инструкции / Official reference

- [GitHub CLI authentication](https://cli.github.com/manual/gh_auth_login)
- [Configure Git credentials](https://cli.github.com/manual/gh_auth_setup-git)
- [Create a repository](https://cli.github.com/manual/gh_repo_create)
- [Create a release](https://cli.github.com/manual/gh_release_create)
- [Repository visibility](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility)
