import SwiftUI
import AppTransferCore

@MainActor final class Preferences: ObservableObject {
    private let defaults:UserDefaults
    @Published var language:String {didSet{defaults.set(language,forKey:"language")}}
    @Published var theme:String {didSet{defaults.set(theme,forKey:"theme")}}
    @Published var density:String {didSet{defaults.set(density,forKey:"density")}}
    @Published var libraryVisible:Bool {didSet{defaults.set(libraryVisible,forKey:"libraryVisible")}}
    @Published var queueVisible:Bool {didSet{defaults.set(queueVisible,forKey:"queueVisible")}}
    @Published var queueBodyHeight:Double {didSet{defaults.set(queueBodyHeight,forKey:"queueBodyHeight")}}
    init(defaults:UserDefaults = .standard){self.defaults=defaults;language=defaults.string(forKey:"language") ?? (Locale.preferredLanguages.first?.hasPrefix("ru")==true ? "ru":"en");theme=defaults.string(forKey:"theme") ?? "system";density=defaults.string(forKey:"density") ?? "compact";libraryVisible=defaults.object(forKey:"libraryVisible")==nil ? true:defaults.bool(forKey:"libraryVisible");queueVisible=defaults.object(forKey:"queueVisible")==nil ? true:defaults.bool(forKey:"queueVisible");let savedHeight=defaults.object(forKey:"queueBodyHeight") as? Double ?? 240;queueBodyHeight=savedHeight.isFinite ? min(900,max(80,savedHeight)):240}
    func t(_ ru:String,_ en:String)->String{language=="ru" ? ru:en}
    var rowHeight:CGFloat{density=="compact" ? 46:57}
    var colorScheme:ColorScheme?{theme=="light" ? .light:theme=="dark" ? .dark:nil}
    func accountReason(_ reason:AccountSelectionReason?)->String {
        switch reason {
        case .metadataOwner:return t("По метаданным приложения","From app metadata")
        case .defaultAccount:return t("Аккаунт по умолчанию","Default account")
        case .onlyAccount:return t("Единственный доступный аккаунт","Only available account")
        case .explicit:return t("Выбран для этой задачи","Chosen for this task")
        case .unresolved:return t("Выберите аккаунт App Store","Choose an App Store account")
        case .none:return t("Аккаунт сохранён в задаче","Account saved with this task")
        }
    }
    func downloadAccountLine(_ email:String?,downloading:Bool=false)->String {
        guard let email,!email.isEmpty else{return t("Для скачивания нужен аккаунт App Store","An App Store account is required to download")}
        return downloading ? t("Скачивается через: \(email)","Downloading via: \(email)") : t("Скачать через: \(email)","Download via: \(email)")
    }
    func archiveAccountLines(_ context:ArchiveAccountContext?)->[String] {
        guard let context else{return [t("Аккаунт IPA неизвестен","IPA account unknown")]}
        var lines:[String]=[]
        if let email=context.downloadAccountEmail {
            lines.append(t("Скачано через: \(email)","Downloaded via: \(email)"))
        }else if context.origin == .imported {
            lines.append(t("Импортированный IPA","Imported IPA"))
        }else {
            lines.append(t("Аккаунт скачивания неизвестен","Download account unknown"))
        }
        if let email=context.metadataOwnerEmail,context.downloadAccountEmail==nil || context.hasAccountConflict {
            lines.append(t("Аккаунт из метаданных IPA: \(email)","Account in IPA metadata: \(email)"))
        }
        if context.suggestedAccountEmail==nil && !context.hasAccountConflict {lines.append(t("Аккаунт для iPhone неизвестен","Account for iPhone unknown"))}
        return lines
    }
    func iPhoneAccountHint(_ context:ArchiveAccountContext?)->String {
        if context?.hasAccountConflict==true {return t("Аккаунты скачивания и IPA различаются. Аккаунт для запуска на iPhone не подтверждён.","Download and IPA accounts differ. The account needed to launch on iPhone is unconfirmed.")}
        if let email=context?.suggestedAccountEmail {return t("На iPhone может потребоваться: \(email)","May be required on iPhone: \(email)")}
        return t("На iPhone может потребоваться аккаунт, которым получен IPA; определить его не удалось.","iPhone may require the account used to obtain the IPA; it could not be identified.")
    }
    func installedMessage(_ context:ArchiveAccountContext?)->String {
        t("Установка подтверждена. Откройте приложение на iPhone.","Installation confirmed. Open the app on iPhone.")+" "+iPhoneAccountHint(context)
    }
    func jobAccountLine(_ job:TransferJob)->String {
        if let context=job.archiveAccounts {return archiveAccountLines(context).first ?? t("Установка из библиотеки","Installing from library")}
        if job.libraryID != nil {return t("IPA из библиотеки · аккаунт IPA неизвестен","Library IPA · IPA account unknown")}
        if job.stage.terminal,let email=job.accountEmail {return t("Аккаунт в задаче: \(email)","Account recorded in task: \(email)")}
        return downloadAccountLine(job.accountEmail,downloading:job.stage == .downloading)
    }
    func storefrontRegion(_ storefront:String?)->String? {
        guard let storefront else{return nil}
        let code=storefront.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
        // Numeric Apple storefront identifiers are not ISO country codes.
        guard code.count==2,code.unicodeScalars.allSatisfy({CharacterSet.letters.contains($0)}),Locale.Region.isoRegions.contains(where:{$0.identifier==code}) else{return nil}
        return Locale(identifier:language=="ru" ? "ru_RU":"en_US").localizedString(forRegionCode:code)
    }
    func stageTitle(_ stage:JobStage)->String {
        switch stage {
        case .queued:return t("В очереди","Queued")
        case .resolving:return t("Подготовка","Preparing")
        case .awaitingAccount:return t("Нужен аккаунт","Account required")
        case .awaitingDevice:return t("Ожидание iPhone","Waiting for iPhone")
        case .awaitingVersionChoice:return t("Выбор версии","Choose a version")
        case .downloading:return t("Скачивание","Downloading")
        case .validating:return t("Проверка IPA","Verifying IPA")
        case .uploading:return t("Отправка на iPhone","Uploading to iPhone")
        case .installing:return t("Установка","Installing")
        case .verifying:return t("Проверка на устройстве","Verifying installation")
        case .succeeded:return t("Готово","Completed")
        case .skipped:return t("Уже установлено","Already installed")
        case .failed:return t("Ошибка","Failed")
        case .canceled:return t("Отменено","Canceled")
        case .interrupted:return t("Прервано — проверьте и повторите","Interrupted — verify and retry")
        }
    }
    func failureMessage(_ code:String?,fallback:String?)->String {
        let values:[String:(String,String)]=[
            "deviceUnavailable":("Подключите нужный iPhone по USB.","Connect the destination iPhone via USB."),
            "deviceLocked":("Разблокируйте iPhone кодом и повторите.","Unlock the iPhone with its passcode and retry."),
            "trustRequired":("Разблокируйте iPhone и подтвердите доверие этому Mac.","Unlock the iPhone and trust this Mac."),
            "licenseRequired":("Apple не разрешает скачивание под выбранным аккаунтом. Выберите аккаунт, под которым получено приложение.","Apple does not allow this download with the selected account. Choose the account used to obtain the app."),
            "accountRequired":("Выберите Apple Account для скачивания.","Choose an Apple Account for this download."),
            "authenticationRequired":("Войдите в Apple Account ещё раз.","Sign in to the Apple Account again."),
            "sessionExpired":("Сессия истекла. Войдите снова.","The session expired. Sign in again."),
            "versionUnavailable":("Исходная версия недоступна. Проверьте предлагаемую версию перед продолжением.","The source version is unavailable. Review the alternative before continuing."),
            "libraryBusy":("IPA используется очередью. Отмените ожидающие задачи или дождитесь завершения.","The queue is using this IPA. Cancel its waiting tasks or wait for completion."),
            "unsupportedApp":("Недостаточно метаданных App Store или приложение установлено через TestFlight.","App Store metadata is missing or the app was installed through TestFlight."),
            "invalidArchive":("Архив IPA повреждён или имеет неподдерживаемую структуру.","The IPA is damaged or has an unsupported structure."),
            "wrongBundle":("Скачанный IPA относится к другому приложению.","The downloaded IPA belongs to a different app."),
            "wrongVersion":("Скачанный IPA не соответствует выбранной версии.","The downloaded IPA does not match the selected version."),
            "missingArchive":("Файл IPA отсутствует. Скачайте или импортируйте его заново.","The IPA file is missing. Download or import it again."),
            "noSpace":("На iPhone недостаточно свободного места.","There is not enough free storage on the iPhone."),
            "incompatibleOS":("Для приложения нужна более новая iOS.","The app requires a newer version of iOS."),
            "incompatibleDevice":("Этот IPA не поддерживает iPhone.","This IPA does not support iPhone."),
            "verificationFailed":("iPhone не подтвердил установку нужной версии. Обновите список перед повтором.","The iPhone did not confirm the requested version. Refresh before retrying."),
            "helperUnavailable":("Не удалось запустить компонент App Store. Проверьте целостность приложения.","The App Store component could not start. Verify the application bundle."),
            "network":("Ошибка сети. Проверьте подключение и повторите.","Network request failed. Check the connection and retry.")
            ,"keychain.unavailable":("Не удалось открыть Связку ключей macOS. Проверьте системный запрос доступа и повторите.","macOS Keychain is unavailable. Check the system access prompt and retry.")
            ,"account.busy":("Аккаунт занят другой операцией. Дождитесь завершения или отмените её.","This account is busy. Wait for its operation or cancel it.")
            ,"account.mismatch":("Этот вход относится к другому аккаунту. Добавьте его отдельно.","This sign-in belongs to a different account. Add it separately.")
            ,"auth.timeout":("Время ожидания кода истекло. Начните вход заново.","The verification code timed out. Sign in again.")
            ,"auth.tooManyAttempts":("Слишком много неверных кодов. Начните вход заново.","Too many incorrect codes. Sign in again.")
            ,"auth.busy":("Проверка кода уже выполняется. Дождитесь результата.","Verification is already running. Wait for the result.")
            ,"apple.requestFailed":("Apple отклонила запрос. Проверьте аккаунт, доступность приложения и соединение.","Apple rejected the request. Check the account, app availability, and connection.")
            ,"archiveChanged":("Сохранённый IPA изменился. Скачайте или импортируйте его заново.","The saved IPA changed. Download or import it again.")
            ,"installationFailed":("iPhone отклонил установку. Обновите список и проверьте фактическое состояние приложения перед повтором.","The iPhone rejected installation. Refresh and check the app's actual state before retrying.")
            ,"deviceTimeout":("iPhone не ответил вовремя. Проверьте подключение и состояние приложения перед повтором.","The iPhone did not respond in time. Check its connection and app state before retrying.")
            ,"deviceError":("Не удалось выполнить операцию с iPhone. Разблокируйте его, проверьте подключение и повторите.","The iPhone operation failed. Unlock it, check the connection, and retry.")
            ,"unsafePath":("Файл находится за пределами управляемой библиотеки.","The file is outside the managed library.")
            ,"schema":("Версия сохранённой библиотеки или очереди не поддерживается этой сборкой.","The saved library or queue version is not supported by this build.")
            ,"output.invalid":("Не удалось создать временный файл в библиотеке. Проверьте доступ к её папке.","Could not create a staging file in the library. Check access to its folder.")
            ,"request.invalid":("Компонент App Store отклонил параметры запроса. Повторите действие.","The App Store component rejected the request parameters. Retry the action.")
            ,"canceled":("Операция отменена.","Operation canceled.")
        ]
        if let code,let pair=values[code]{return t(pair.0,pair.1)}
        return fallback.map(localizedMessage) ?? t("Операция не выполнена.","The operation failed.")
    }
    func localizedMessage(_ message:String)->String {
        guard language=="ru" else{return message}
        let messages:[String:String]=[
            "The previous operation was interrupted. Reconnect the device and retry to verify its state first.":"Предыдущая операция прервана. Подключите iPhone и повторите: сначала проверим его состояние.",
            "The device will finish its current installation before the queue stops.":"iPhone завершит текущую установку, затем очередь остановится.",
            "The app is already installed on this device.":"Приложение уже установлено на этом iPhone.",
            "Choose an Apple Account to download this application.":"Выберите Apple Account для скачивания приложения.",
            "Sign in to the Apple Account used for this application.":"Войдите в Apple Account, под которым получено приложение.",
            "The exact source version is unavailable. Review the available version before continuing.":"Исходная версия недоступна. Проверьте предлагаемую версию перед продолжением.",
            "Choose whether to use the available version.":"Выберите, использовать ли доступную версию.",
            "Saved to the local library.":"Сохранено в библиотеку на этом Mac.",
            "Installed and verified. Open the app on the iPhone; its Apple Account or app login may still be required.":"Установка подтверждена. Откройте приложение на iPhone: может потребоваться его Apple Account или обычный вход.",
            "Removed from library; installed copies remain on devices.":"Удалено из библиотеки. Приложения на телефонах сохранены.",
            "Library":"Библиотека","Trash":"Корзина"
        ]
        return messages[message] ?? message
    }
}
