# GitHub CLI и приватная поставка / GitHub CLI and private delivery

Repository: [`Daveedick/iphone-app-transfer`](https://github.com/Daveedick/iphone-app-transfer). Product: **iPhone App Transfer**. The current delivery is **private**, including prerelease [`v0.1.4`](https://github.com/Daveedick/iphone-app-transfer/releases/tag/v0.1.4). Public visibility is a later, separate decision. Check actual repository/release state before repeating any creation command.

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

## Первый commit и private repository

Работать из корня проекта. Сначала проверить `git status`, текущую ветку, `git remote -v`, идентичность автора и состав staged changes. Если `origin` уже существует, сверить его адрес и удалённую историю; не выполнять force push, reset или повторное создание вслепую.

Перед первым коммитом проверить весь будущий набор файлов, включая изображения. `.gitignore` исключает `dist`, `.build`, IPA, личные дампы, секреты и private-логи. Приватный репозиторий не заменяет этот контроль: позднее открывается и история. Vendored ipatool, патчи, lockfiles, notices и лицензии зависимостей нужны для сборки и должны остаться в исходниках. Лицензия собственного кода ещё не выбрана.

После проверки и только если соответствующие шаги ещё не выполнены:

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

Пользователь уже разрешил текущую приватную поставку; повторный вопрос на каждый commit/push не нужен. При существующем репозитории применять обычные последующие commit/push после проверки remote.

Подтверждение результата:

```sh
gh repo view Daveedick/iphone-app-transfer --json nameWithOwner,isPrivate,visibility,url
git remote -v
git rev-parse HEAD
git ls-remote origin refs/heads/main
```

Ожидается `isPrivate: true`, `visibility: PRIVATE` и одинаковый SHA локального `HEAD`/удалённого `main`. Описание и release notes не должны обещать завершённые проверки второго телефона, двух аккаунтов или чистого Mac.

## Если API работает, а Git push зависает

В первой отправке на Mac автора API GitHub работал, но HTTP-транспорт Git задержал завершение. Перед повтором проверьте удалённый SHA: коммит уже мог попасть на сервер. Помог однократный запуск с настройками только для команды:

```sh
git -c http.version=HTTP/1.1 \
  -c http.postBuffer=10485760 \
  -c http.lowSpeedLimit=1024 \
  -c http.lowSpeedTime=30 push -u origin main
```

Это не отключает TLS-проверку и не меняет глобальные настройки Git. Не запускайте повторную авторизацию, если `gh api user --jq .login` уже работает. В ограниченной среде HTTP 401 при чтении Keychain может требовать разрешённого запуска конкретной операции вне sandbox; токен выводить не нужно.

## Приватный prerelease

Сначала собрать и проверить `.app`/DMG по [инструкции сборки](../scripts/README.md). Изменение README не подтверждает существование рабочего DMG. Установка через GUI на второй телефон и чистый Mac остаётся pending до фактического теста.

Тег и release должны относиться к проверенному коммиту. Если `v0.1.4` уже существует, сравнить target и артефакты; не перемещать опубликованный тег и не заменять чужой файл вслепую. После подготовки release notes в обычном UTF-8 файле:

```sh
git tag v0.1.4
git push origin v0.1.4
gh release create v0.1.4 \
  --repo Daveedick/iphone-app-transfer \
  --verify-tag \
  --prerelease \
  --title 'iPhone App Transfer 0.1.4 — private preview' \
  --notes-file /path/to/release-notes.md \
  dist/iPhone-App-Transfer-0.1.4-arm64.dmg \
  dist/iPhone-App-Transfer-0.1.4-arm64.dmg.sha256
```

`/path/to/release-notes.md` — явный placeholder: заменить реальным путём к подготовленному файлу. Release notes включают RU/EN описание, подтверждённые проверки, checksum и список pending. Приватность задаётся репозиторием; отметка prerelease сама по себе не делает открытый репозиторий приватным.

После публикации проверить `gh release view`, скачать оба файла в отдельный временный каталог и выполнить `shasum -a 256 -c iPhone-App-Transfer-0.1.4-arm64.dmg.sha256` из этого каталога. Отдельно клонировать репозиторий в новую папку и убедиться, что присутствуют исходники/helper/vendored core, а личные данные и сборочные артефакты отсутствуют. Свежий clone на том же Mac не заменяет установку на чистом Mac.

## Перед переходом в public

Репозиторий остаётся приватным, пока пользователь явно не решит его открыть. Перед этим:

1. Проверить полный GUI install/readback/launch на втором телефоне и работу с двумя Apple Account.
2. Проверить DMG, допустимый Gatekeeper-flow и первый login/download на Mac без Homebrew, Go, ipatool, старых сессий и runtime-кэшей.
3. Устранить обнаруженные ошибки и обновить обе инструкции/known limits по фактам.
4. Выбрать лицензию собственного кода с учётом состава зависимостей и обязательств по их исходникам/notices.
5. Повторно проверить всю Git-историю, release assets, изображения, issue templates и документацию на секреты и личные данные.
6. Получить прямое решение пользователя об открытии; затем изменить visibility и подтвердить публичное чтение без авторизации.

При обнаружении действующего секрета одного удаления файла из последнего коммита недостаточно: сначала отозвать секрет и отдельно обработать историю. Это не повод заранее публиковать чувствительные данные даже в private.

## English guide

GitHub CLI handles repository and release operations from Terminal; the browser is needed only for initial authorization or a later reauthorization. On the author's Mac, authentication as `Daveedick` has already been checked. Start with `gh api user --jq .login`; do not repeat `gh auth login` when that succeeds. `gh auth setup-git --hostname github.com` configures Git to use the CLI's credentials. Never print or share a token for troubleshooting.

The commands above cover first-time private creation, verification and the `v0.1.4` prerelease. Inspect existing local/remote state before using them. Review the staged tree for secrets, real phone inventories, IPA files and personal screenshots before the first commit. Keep dependency source/patches/licenses needed by the bundled helper. Exclude `.build` and `dist`; upload the DMG and its checksum as release assets instead of Git source files.

If Git transport stalls while the CLI API succeeds, inspect the remote SHA before retrying; the scoped HTTP/1.1 command above does not weaken TLS verification or change global Git settings.

Verify `PRIVATE`, the remote commit SHA, downloaded asset checksum and a fresh clone. None of these checks proves the second-phone installation or a clean-Mac first run. The repository remains private until the owner explicitly chooses public distribution after live testing, license selection and a full-history privacy review. A prerelease flag does not control repository visibility.

## Официальные инструкции / Official reference

- [GitHub CLI authentication](https://cli.github.com/manual/gh_auth_login)
- [Configure Git credentials](https://cli.github.com/manual/gh_auth_setup-git)
- [Create a repository](https://cli.github.com/manual/gh_repo_create)
- [Create a release](https://cli.github.com/manual/gh_release_create)
- [Repository visibility](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility)
