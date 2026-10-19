import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AppTransferCore

/// A single physical pixel marks structural boundaries; rows use spacing.
private struct WorkspaceRule: View {
    var vertical = false
    @Environment(\.displayScale) private var scale
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Rectangle().fill(Color.primary.opacity(contrast == .increased ? 0.3 : 0.09))
            .frame(width: vertical ? 1 / scale : nil, height: vertical ? nil : 1 / scale)
            .accessibilityHidden(true)
    }
}

private struct QuietInput: ViewModifier {
    var focused: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).focusEffectDisabled().font(.system(size: 12))
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                if focused { RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.24), lineWidth: 1) }
            }
    }
}

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var librarySearch = ""
    @State private var deviceSearch: [String: String] = [:]
    @State private var libraryTargeted = false
    @State private var edgeDirection = 0
    @State private var scrollIndex = 0
    @FocusState private var focusedLibraryID: String?
    @State private var libraryKeyboardNavigation = false

    init(model: AppModel) {
        self.model = model
        self.prefs = model.prefs
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                topBar
                WorkspaceRule()
                if model.currentTab == "activity" {
                    ActivityView(model: model, prefs: prefs)
                } else {
                    deviceWorkspace
                    if !model.selectedIDs.isEmpty { selectionBar }
                    // Keep the device header/search and a few rows usable even
                    // when the queue is enlarged or the window becomes smaller.
                    TransferQueuePanel(model: model, prefs: prefs, maximumBodyHeight: max(80, geometry.size.height - (model.selectedIDs.isEmpty ? 370 : 414) - QueueResizeHandle.height - prefs.rowHeight))
                }
                footer
            }
        }
        .background {
            ZStack {
                FrostedWorkspaceBackground(reducedTransparency: reduceTransparency)
                Color(nsColor: .windowBackgroundColor).opacity(reduceTransparency ? 1 : 0.78)
            }
        }
        .background(NativeWindowChrome())
        .preferredColorScheme(prefs.colorScheme)
        .frame(minWidth: 760, minHeight: 560)
        .overlay(alignment: .top) { errorBanner.padding(.top, 61) }
        .alert(prefs.t("Удалить из библиотеки?", "Delete from Library?"), isPresented: deletionPresented) {
            Button(prefs.t("Отмена", "Cancel"), role: .cancel) { model.pendingDeletion = [] }
            Button(prefs.t("Переместить в Корзину", "Move to Trash"), role: .destructive) { model.confirmDelete() }
        } message: {
            Text(deletionMessage)
        }
        .onChange(of: model.showSettings) { _, shown in if shown { model.showAccounts = false } }
        .onChange(of: model.showAccounts) { _, shown in if shown { model.showSettings = false } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            model.showSettings = false; model.showAccounts = false
        }
        .onExitCommand { model.showSettings = false; model.showAccounts = false }
        .onChange(of: focusedLibraryID) { _, _ in
            if NSApp.currentEvent?.type == .keyDown { libraryKeyboardNavigation = true }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: prefs.libraryVisible)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: prefs.queueVisible)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("iPhone App Transfer").font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 12)
            HStack(spacing: 2) {
                navigationTab("devices", title: prefs.t("Устройства", "Devices"))
                navigationTab("activity", title: prefs.t("Журнал", "Activity"))
            }
            Spacer(minLength: 12)
            Button { model.showAccounts.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle")
                    Text(prefs.t("Аккаунты", "Accounts"))
                    if !model.accounts.isEmpty { Text("\(model.accounts.count)").font(.system(size: 10)).foregroundStyle(.secondary) }
                }
            }
            .buttonStyle(UtilityButtonStyle(borderless: true))
            .background(model.showAccounts ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .popover(isPresented: $model.showAccounts, arrowEdge: .top) { AccountsPopover(model: model, prefs: prefs) }
            IconUtilityButton(symbol: "slider.horizontal.3", label: prefs.t("Настройки · ⌘,", "Settings · ⌘,")) { model.showSettings.toggle() }
                .popover(isPresented: $model.showSettings, arrowEdge: .top) { SettingsPopover(prefs: prefs) }
        }
        .padding(.horizontal, 17).frame(height: 52)
    }

    private func navigationTab(_ tab: String, title: String) -> some View {
        Button { model.currentTab = tab } label: { Text(title) }
            .buttonStyle(UtilityButtonStyle(borderless: true))
            .background(model.currentTab == tab ? Color.primary.opacity(0.075) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .accessibilityAddTraits(model.currentTab == tab ? [.isSelected] : [])
    }

    private var deviceWorkspace: some View {
        ScrollViewReader { reader in
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button { prefs.libraryVisible.toggle() } label: {
                        HStack(spacing: 7) {
                            Label(prefs.t("Библиотека", "Library"), systemImage: "sidebar.left")
                            Text("⌘S").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(UtilityButtonStyle(borderless: true))
                    .onDrop(of: AppTransferDragTypes, delegate: TextPayloadDropDelegate(receive: { model.handleDrop($0, to: nil) }, hover: { over in if over { prefs.libraryVisible = true } }))
                    Spacer(minLength: 8)
                    if model.isRefreshing { ProgressView().controlSize(.mini) }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(Array(model.devices.enumerated()), id: \.element.id) { index, phone in
                                Button {
                                    scrollIndex = index
                                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { reader.scrollTo(phone.id, anchor: .leading) }
                                } label: {
                                    HStack(spacing: 5) {
                                        Circle().fill(phone.state == "connected" ? Color.green : Color.orange).frame(width: 4, height: 4)
                                        Text(navigationName(phone)).font(.system(size: 10.5)).lineLimit(1)
                                    }
                                }
                                .buttonStyle(UtilityButtonStyle(borderless: true))
                                .background(scrollIndex == index ? Color.primary.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 7))
                                .help(phone.name + " · " + phone.model + " · " + phone.shortID)
                            }
                        }
                    }.fixedSize(horizontal: false, vertical: true)
                    IconUtilityButton(symbol: "arrow.clockwise", label: prefs.t("Обновить устройства", "Refresh devices")) { model.refresh() }
                        .disabled(model.isRefreshing)
                }.padding(.horizontal, 12).frame(height: 40)
                HStack(spacing: 0) {
                    if prefs.libraryVisible {
                        librarySidebar.frame(width: 220).transition(.move(edge: .leading).combined(with: .opacity))
                        WorkspaceRule(vertical: true)
                    }
                    if model.devices.isEmpty {
                        WorkspaceEmptyState(symbol: "iphone.and.arrow.forward", title: prefs.t("Подключите iPhone", "Connect an iPhone"), message: prefs.t("Подключите телефон к Mac по USB, разблокируйте его и подтвердите доверие этому компьютеру. Затем выберите приложения для библиотеки или другого устройства.", "Connect your phone to this Mac via USB, unlock it, and trust this computer. Then save apps to the library or transfer them to another device."))
                    } else {
                        GeometryReader { geometry in
                            let visibleColumns = max(1, min(3, model.devices.count))
                            let width = max(260, (geometry.size.width - CGFloat(visibleColumns - 1)) / CGFloat(visibleColumns))
                            ScrollView(.horizontal) {
                                HStack(spacing: 0) {
                                    ForEach(Array(model.devices.enumerated()), id: \.element.id) { index, phone in
                                        DeviceColumn(model: model, prefs: prefs, phone: phone, search: searchBinding(phone.id))
                                            .frame(width: width).id(phone.id)
                                        if index < model.devices.count - 1 { WorkspaceRule(vertical: true) }
                                    }
                                }.frame(minHeight: geometry.size.height)
                            }
                            .overlay(alignment: .leading) { dragEdge(-1, reader: reader) }
                            .overlay(alignment: .trailing) { dragEdge(1, reader: reader) }
                        }
                    }
                }
            }
            .task(id: edgeDirection) {
                guard edgeDirection != 0 else { return }
                while !Task.isCancelled && edgeDirection != 0 {
                    let next = min(max(0, scrollIndex + edgeDirection), max(0, model.devices.count - 1))
                    if next != scrollIndex, model.devices.indices.contains(next) {
                        scrollIndex = next
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { reader.scrollTo(model.devices[next].id, anchor: .leading) }
                    }
                    try? await Task.sleep(for: .milliseconds(450))
                }
            }
        }
    }

    private func dragEdge(_ direction: Int, reader: ScrollViewProxy) -> some View {
        Color.clear.frame(width: 18)
            .contentShape(Rectangle())
            .onDrop(of: AppTransferDragTypes, delegate: EdgeScrollDropDelegate(entered: { edgeDirection = direction }, exited: { edgeDirection = 0 }))
            .accessibilityHidden(true)
    }

    private var librarySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(prefs.t("Библиотека", "Library")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                    .help(prefs.t("Здесь хранятся скачанные приложения для установки на другие устройства. Может потребоваться Apple Account, под которым они скачаны.", "Downloaded apps are stored here for installation on other devices. The Apple Account used to obtain an app may be required."))
            }.frame(height: 68)
            WorkspaceSearchField(text: $librarySearch, prompt: prefs.t("Найти приложение", "Find an app"), clearLabel: prefs.t("Очистить поиск", "Clear search"))
            Text("\(model.library.count) IPA · \(readableBytes(model.library.reduce(0) { $0 + $1.bytes }))")
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 12).padding(.bottom, 8)
            if model.library.isEmpty {
                VStack(spacing: 11) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 21, weight: .light))
                    Text(prefs.t("Перетащите сюда приложение с телефона", "Drag an app here from a phone")).font(.system(size: 12)).multilineTextAlignment(.center)
                    Text(prefs.t("Сохраним IPA без установки на другое устройство", "Save the IPA without installing it on another device")).font(.system(size: 10.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary).padding(.horizontal, 13).padding(.vertical, 25)
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredLibrary) { item in
                            libraryRow(item)
                        }
                        if filteredLibrary.isEmpty { Text(prefs.t("Ничего не найдено", "No matching apps")).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20) }
                    }.padding(.bottom, 12).accessibilityElement(children: .contain)
                }.accessibilityLabel(prefs.t("Приложения в библиотеке", "Library apps"))
            }
            Button { model.importIPA() } label: { Label(prefs.t("Импортировать IPA…", "Import IPA…"), systemImage: "plus") }
                .buttonStyle(UtilityButtonStyle(borderless: true)).padding(.vertical, 10)
            Label(prefs.t("Хранится на этом Mac", "Stored on this Mac"), systemImage: "internaldrive")
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(.bottom, 15)
        }
        .padding(.horizontal, 12)
        .background(Color.primary.opacity(0.018))
        .overlay {
            if libraryTargeted {
                RoundedRectangle(cornerRadius: 9).strokeBorder(Color.accentColor.opacity(0.75), lineWidth: contrast == .increased ? 2 : 1).padding(5)
                    .overlay(alignment: .bottom) { Text(prefs.t("Скачать в библиотеку", "Download to Library")).font(.system(size: 12, weight: .medium)).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(.bottom, 52) }
            }
        }
        .onDrop(of: AppTransferDragTypes, delegate: TextPayloadDropDelegate(receive: { model.handleDrop($0, to: nil) }, hover: { libraryTargeted = $0 }))
    }

    private func libraryRow(_ item: AppTransferCore.LibraryItem) -> some View {
        let id = item.id.uuidString
        return AppListRow(name: item.app.name, detail: "\(item.app.version) · \(item.missing ? prefs.t("Файл отсутствует", "File missing") : readableBytes(item.bytes))", image: model.libraryIcon(item), selected: model.selectedLocation == "library" && model.selectedIDs.contains(id), comfortable: prefs.density == "comfortable", symbol: item.missing ? "exclamationmark.triangle" : nil, warning: item.missing, keyboardFocused: focusedLibraryID == id && libraryKeyboardNavigation, accessibilitySelect: { model.select(id: id, location: "library", extend: false) })
            .onTapGesture { select(id, location: "library") }
            .focusable().focusEffectDisabled().focused($focusedLibraryID, equals: id)
            .onKeyPress(.space, phases: [.down, .repeat]) { press in
                libraryKeyboardNavigation = true
                model.select(id: id, location: "library", extend: press.modifiers.contains(.command), range: press.modifiers.contains(.shift), orderedIDs: filteredLibrary.map { $0.id.uuidString })
                return .handled
            }
            .onKeyPress(.return) { select(id, location: "library"); libraryKeyboardNavigation = true; return .handled }
            .onKeyPress(.downArrow, phases: [.down, .repeat]) { press in moveLibraryFocus(from: id, by: 1, range: press.modifiers.contains(.shift)); return .handled }
            .onKeyPress(.upArrow, phases: [.down, .repeat]) { press in moveLibraryFocus(from: id, by: -1, range: press.modifiers.contains(.shift)); return .handled }
            .onDrag { NSItemProvider(object: model.dropPayload(for: id, location: "library") as NSString) }
            .contextMenu {
                ForEach(model.devices) { phone in
                    Button(prefs.t("Установить на ", "Install on ") + phone.name) { selectForAction(id, location: "library"); model.transferSelection(to: phone.id) }.disabled(item.missing)
                }
                Divider()
                Button(role: .destructive) { selectForAction(id, location: "library"); model.requestDeleteSelection() } label: { Label(prefs.t("Удалить из библиотеки…", "Delete from Library…"), systemImage: "trash") }
                Divider()
                Text(item.app.bundleID)
                Text(prefs.t("Сборка: ", "Build: ") + (item.app.build.isEmpty ? "—" : item.app.build))
                Text(item.accountEmail ?? prefs.t("Аккаунт не указан", "Account unspecified"))
                if !item.hasSinf { Text(prefs.t("В IPA нет метаданных лицензии App Store", "No App Store license metadata in this IPA")) }
            }
            .help("\(item.app.name) \(item.app.version)\n\(item.accountEmail ?? prefs.t("Аккаунт не указан", "Account unspecified"))")
    }

    private var selectionBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Text(selectionTitle).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text("· " + selectionLocationName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 10)
            if model.selectedLocation != "library" {
                Button { model.transferSelection(to: nil) } label: { Label(prefs.t("В библиотеку", "Save to Library"), systemImage: "square.and.arrow.down") }.buttonStyle(UtilityButtonStyle())
            } else {
                Button(role: .destructive) { model.requestDeleteSelection() } label: { Label(prefs.t("Удалить…", "Delete…"), systemImage: "trash") }.buttonStyle(UtilityButtonStyle()).disabled(!prefs.libraryVisible)
            }
            Menu {
                ForEach(model.devices.filter { $0.id != model.selectedLocation }) { phone in
                    Button(phone.name + " · " + phone.shortID) { model.transferSelection(to: phone.id) }
                }
            } label: { Label(prefs.t("Установить на…", "Install on…"), systemImage: "arrow.right") }
            .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
            .disabled(model.devices.filter { $0.id != model.selectedLocation }.isEmpty)
            Button { model.selectedIDs = [] } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).help(prefs.t("Снять выделение", "Clear selection"))
        }
        .padding(.horizontal, 16).frame(height: 44)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: model.isDemo ? "play.rectangle" : "cable.connector").font(.system(size: 11))
            Text(model.isDemo ? prefs.t("Демонстрация · синтетические данные", "Demo · synthetic data") : prefs.t("Подключение по USB", "USB connection"))
            if !model.devices.isEmpty { Text("· " + prefs.t("Перетаскивайте приложения между колонками", "Drag apps between columns")).lineLimit(1) }
            Spacer()
            if let message = model.statusMessage { Text(message).lineLimit(1) }
            else { Text(prefs.t("Приложения переносятся без локальных данных", "App transfers do not include local data")).lineLimit(1) }
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 16).frame(height: 30)
    }

    @ViewBuilder private var errorBanner: some View {
        if let message = model.globalError {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 10)
                Button { model.dismissError() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel(prefs.t("Закрыть", "Dismiss"))
            }
            .padding(13).frame(maxWidth: 650).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 6).padding(.horizontal, 20)
        }
    }

    private var filteredLibrary: [AppTransferCore.LibraryItem] {
        model.library.filter { librarySearch.isEmpty || $0.app.name.localizedCaseInsensitiveContains(librarySearch) || $0.app.bundleID.localizedCaseInsensitiveContains(librarySearch) || ($0.accountEmail?.localizedCaseInsensitiveContains(librarySearch) ?? false) }
    }
    private var selectionLocationName: String { model.selectedLocation == "library" ? prefs.t("Библиотека", "Library") : model.devices.first { $0.id == model.selectedLocation }?.name ?? "" }
    private var selectionTitle: String {
        if model.selectedIDs.count == 1, let id = model.selectedIDs.first {
            if model.selectedLocation == "library", let item = model.library.first(where: { $0.id.uuidString == id }) { return item.app.name }
            if let app = model.devices.first(where: { $0.id == model.selectedLocation })?.apps.first(where: { $0.id == id }) { return app.name }
        }
        return prefs.t("Выбрано: ", "Selected: ") + "\(model.selectedIDs.count)"
    }
    private func navigationName(_ phone: Phone) -> String {
        model.devices.filter { $0.name == phone.name }.count > 1 ? phone.model + " · " + phone.shortID : phone.name
    }
    private var deletionPresented: Binding<Bool> { Binding(get: { !model.pendingDeletion.isEmpty }, set: { if !$0 { model.pendingDeletion = [] } }) }
    private var deletionMessage: String {
        let names = model.pendingDeletion.prefix(5).map { "\($0.app.name) \($0.app.version)" }.joined(separator: ", ")
        let suffix = model.pendingDeletion.count > 5 ? " +\(model.pendingDeletion.count - 5)" : ""
        return names + suffix + "\n\n" + prefs.t("IPA будут перемещены в Корзину Mac. Установленные приложения и их данные останутся на телефонах. Используемые очередью архивы удалить нельзя.", "The IPA files will move to this Mac’s Trash. Installed apps and their data remain on the phones. Archives in use by the queue cannot be deleted.")
    }
    private func searchBinding(_ id: String) -> Binding<String> { Binding(get: { deviceSearch[id] ?? "" }, set: { deviceSearch[id] = $0 }) }
    private func select(_ id: String, location: String) {
        if location == "library" { libraryKeyboardNavigation = false; focusedLibraryID = id }
        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        model.select(id: id, location: location, extend: flags.contains(.command), range: flags.contains(.shift), orderedIDs: location == "library" ? filteredLibrary.map { $0.id.uuidString } : nil)
    }
    private func selectForAction(_ id: String, location: String) {
        if model.selectedLocation != location || !model.selectedIDs.contains(id) { model.select(id: id, location: location, extend: false) }
    }
    private func moveLibraryFocus(from id: String, by delta: Int, range: Bool) {
        guard let index = filteredLibrary.firstIndex(where: { $0.id.uuidString == id }), !filteredLibrary.isEmpty else { return }
        let next = filteredLibrary[min(max(0, index + delta), filteredLibrary.count - 1)].id.uuidString
        focusedLibraryID = next
        libraryKeyboardNavigation = true
        model.select(id: next, location: "library", extend: false, range: range, orderedIDs: filteredLibrary.map { $0.id.uuidString })
    }
}

private struct DeviceColumn: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    let phone: Phone
    @Binding var search: String
    @State private var targeted = false
    @State private var keyboardNavigation = false
    @FocusState private var focusedAppID: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "iphone").font(.system(size: 31, weight: .ultraLight)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(phone.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text("\(phone.model) · iOS \(phone.iOS)").font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 2)
                VStack(spacing: 3) {
                    Circle().fill(phone.state == "connected" ? Color.green : Color.orange).frame(width: 5, height: 5)
                    Text(phone.shortID).font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }.frame(height: 68)
            WorkspaceSearchField(text: $search, prompt: prefs.t("Найти приложение", "Find an app"), clearLabel: prefs.t("Очистить поиск", "Clear search"))
            HStack {
                Text(prefs.t("Приложений: ", "Apps: ") + "\(phone.apps.count)")
                Spacer()
                if let bytes = phone.freeBytes { Text(prefs.t("Свободно ", "Free ") + readableBytes(bytes)) }
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 12).padding(.bottom, 8)
            if phone.state != "connected" {
                WorkspaceEmptyState(symbol: phone.state.lowercased().contains("lock") ? "lock.iphone" : "iphone.badge.exclamationmark", title: stateTitle, message: prefs.t("Разблокируйте iPhone, подтвердите доверие Mac и обновите устройства.", "Unlock the iPhone, trust this Mac, and refresh devices."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredApps) { app in appRow(app) }
                        if filteredApps.isEmpty { Text(search.isEmpty ? prefs.t("Список приложений пуст", "No apps on this device") : prefs.t("Ничего не найдено", "No matching apps")).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 25) }
                    }.padding(.bottom, 13).accessibilityElement(children: .contain)
                }.accessibilityLabel(prefs.t("Приложения на ", "Apps on ") + phone.name)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(targeted ? Color.accentColor.opacity(0.07) : Color.clear)
        .overlay {
            if targeted {
                RoundedRectangle(cornerRadius: 9).strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 1).padding(5)
                    .overlay(alignment: .bottom) { Text(prefs.t("Установить на ", "Install on ") + phone.name).font(.system(size: 12, weight: .medium)).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(.bottom, 46) }
            }
        }
        .onDrop(of: AppTransferDragTypes, delegate: TextPayloadDropDelegate(receive: { model.handleDrop($0, to: phone.id) }, hover: { targeted = $0 }))
        .onChange(of: focusedAppID) { _, _ in
            if NSApp.currentEvent?.type == .keyDown { keyboardNavigation = true }
        }
    }
    private func appRow(_ app: AppDescriptor) -> some View {
        AppListRow(name: app.name, detail: app.version + (app.offloaded ? " · " + prefs.t("Сгружено", "Offloaded") : app.testFlight ? " · TestFlight" : ""), image: model.icon(for: app, on: phone.id), selected: model.selectedLocation == phone.id && model.selectedIDs.contains(app.id), comfortable: prefs.density == "comfortable", symbol: app.offloaded ? "icloud.and.arrow.down" : nil, keyboardFocused: focusedAppID == app.id && keyboardNavigation, accessibilitySelect: { model.select(id: app.id, location: phone.id, extend: false) })
            .onTapGesture {
                keyboardNavigation = false
                focusedAppID = app.id
                let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                model.select(id: app.id, location: phone.id, extend: flags.contains(.command), range: flags.contains(.shift), orderedIDs: filteredApps.map(\.id))
            }
            .focusable().focusEffectDisabled().focused($focusedAppID, equals: app.id)
            .onKeyPress(.space, phases: [.down, .repeat]) { press in keyboardNavigation = true; model.select(id: app.id, location: phone.id, extend: press.modifiers.contains(.command), range: press.modifiers.contains(.shift), orderedIDs: filteredApps.map(\.id)); return .handled }
            .onKeyPress(.return) { keyboardNavigation = true; model.select(id: app.id, location: phone.id, extend: false); return .handled }
            .onKeyPress(.downArrow, phases: [.down, .repeat]) { press in moveFocus(from: app.id, by: 1, range: press.modifiers.contains(.shift)); return .handled }
            .onKeyPress(.upArrow, phases: [.down, .repeat]) { press in moveFocus(from: app.id, by: -1, range: press.modifiers.contains(.shift)); return .handled }
            .onDrag { NSItemProvider(object: model.dropPayload(for: app.id, location: phone.id) as NSString) }
            .contextMenu {
                Button { selectForAction(app.id); model.transferSelection(to: nil) } label: { Label(prefs.t("Скачать в библиотеку", "Download to Library"), systemImage: "square.and.arrow.down") }
                ForEach(model.devices.filter { $0.id != phone.id }) { target in
                    Button(prefs.t("Установить на ", "Install on ") + target.name + " · " + target.shortID) { selectForAction(app.id); model.transferSelection(to: target.id) }
                }
                Divider()
                Text(app.bundleID)
                if let email = app.ownerEmail { Text(email) }
                if app.testFlight { Text(prefs.t("TestFlight: загрузка из App Store недоступна", "TestFlight: App Store download unavailable")) }
                else { Text(prefs.t("Возможность скачивания ещё не проверена", "Download availability has not been checked")) }
            }
            .help(app.name + " · " + app.version + "\n" + prefs.t("Доступность скачивания проверяется при переносе", "Download availability is checked during transfer"))
    }
    private var filteredApps: [AppDescriptor] { phone.apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) } }
    private var stateTitle: String {
        let state = phone.state.lowercased()
        if state.contains("lock") { return prefs.t("iPhone заблокирован", "iPhone is locked") }
        if state.contains("trust") || state.contains("pair") { return prefs.t("Нужно доверие iPhone", "Trust this Mac on iPhone") }
        return prefs.t("Устройство недоступно", "Device unavailable")
    }
    private func selectForAction(_ id: String) { if model.selectedLocation != phone.id || !model.selectedIDs.contains(id) { model.select(id: id, location: phone.id, extend: false) } }
    private func moveFocus(from id: String, by delta: Int, range: Bool) {
        guard let index = filteredApps.firstIndex(where: { $0.id == id }), !filteredApps.isEmpty else { return }
        let next = filteredApps[min(max(0, index + delta), filteredApps.count - 1)].id
        focusedAppID = next
        keyboardNavigation = true
        model.select(id: next, location: phone.id, extend: false, range: range, orderedIDs: filteredApps.map(\.id))
    }
}

struct TransferJobRow: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    let job: TransferJob
    private var active: Bool { [.resolving, .downloading, .validating, .uploading, .installing, .verifying].contains(job.stage) }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            summary
            recovery
        }.padding(.vertical, 9)
    }
    private var summary: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(job.stage == .succeeded ? Color.green : stageColor).frame(width: 17)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.app.name).font(.system(size: 12)).foregroundStyle(job.stage.terminal && job.stage != .failed ? Color.secondary : Color.primary).lineLimit(1)
                Text(job.sourceName + " → " + job.targetName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(minWidth: 110, maxWidth: .infinity, alignment: .leading)
            progress
            jobActions
        }
    }
    private var progress: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 8) {
                Text(prefs.stageTitle(job.stage)).font(.system(size: 10.5)).foregroundStyle(stageColor)
                if let value = job.progress, active {
                    Text("\(Int(min(1, max(0, value)) * 100))%").font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if active {
                if let value = job.progress { ProgressView(value: min(1, max(0, value))).controlSize(.mini).frame(width: 190) }
                else { ProgressView().controlSize(.mini) }
            }
        }
    }
    @ViewBuilder private var jobActions: some View {
        if job.stage == .failed || job.stage == .interrupted || job.stage == .awaitingDevice {
            IconUtilityButton(symbol: "arrow.clockwise", label: prefs.t("Повторить", "Retry")) { model.retryJob(job.id) }
        }
        if !job.stage.terminal {
            IconUtilityButton(symbol: "xmark", label: job.stage.deviceMutation ? prefs.t("Остановить после текущей операции", "Stop after current operation") : prefs.t("Отменить задачу", "Cancel task")) { model.cancelJob(job.id) }.disabled(job.cancelRequested)
        }
    }
    @ViewBuilder private var recovery: some View {
        if job.stage == .awaitingAccount { accountRecovery }
        else if job.stage == .awaitingVersionChoice { versionRecovery }
        else if job.stage == .failed || job.stage == .awaitingDevice || job.cancelRequested {
            Text(job.cancelRequested ? prefs.t("Остановим на ближайшей безопасной границе", "Will stop at the next safe boundary") : prefs.failureMessage(job.errorCode, fallback: job.message)).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.leading, 27)
        }
    }
    private var accountRecovery: some View {
        HStack(spacing: 8) {
            Text(prefs.failureMessage(job.errorCode, fallback: job.message)).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 6)
            Menu(prefs.t("Выбрать аккаунт", "Choose account")) {
                ForEach(model.accounts) { account in Button(account.email) { model.selectAccountForJob(jobID: job.id, accountID: account.id) } }
                Divider()
                Button(prefs.t("Добавить аккаунт…", "Add account…")) { model.showAccounts = true }
            }.fixedSize()
        }.padding(.leading, 27)
    }
    private var versionRecovery: some View {
        let caption = prefs.t("Запрошена ", "Requested ") + job.app.version + " · " + prefs.t("доступна ", "available ") + (job.alternative?.version ?? "—")
        return HStack(spacing: 10) {
            Text(caption).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Spacer()
            Button(prefs.t("Использовать эту версию", "Use this version")) { model.acceptAlternative(job.id) }.buttonStyle(UtilityButtonStyle()).disabled(job.alternative == nil)
        }.padding(.leading, 27)
    }
    private var stageColor: Color { job.stage == .failed ? .orange : .secondary }
    private var symbol: String {
        switch job.stage {
        case .succeeded: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .canceled: return "xmark.circle"
        case .skipped: return "checkmark"
        case .awaitingAccount: return "person.crop.circle.badge.questionmark"
        case .awaitingDevice: return "cable.connector"
        case .awaitingVersionChoice: return "arrow.triangle.branch"
        default: return "arrow.right"
        }
    }
}

private struct SettingsPopover: View {
    @ObservedObject var prefs: Preferences
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(prefs.t("Настройки", "Settings")).font(.system(size: 15, weight: .semibold))
            setting(prefs.t("Язык", "Language")) {
                Picker(prefs.t("Язык", "Language"), selection: $prefs.language) { Text("Русский").tag("ru"); Text("English").tag("en") }.pickerStyle(.segmented).labelsHidden()
            }
            setting(prefs.t("Плотность списков", "List density")) {
                Picker(prefs.t("Плотность списков", "List density"), selection: $prefs.density) { Text(prefs.t("Компактная", "Compact")).tag("compact"); Text(prefs.t("Свободная", "Comfortable")).tag("comfortable") }.pickerStyle(.segmented).labelsHidden()
            }
            setting(prefs.t("Оформление", "Appearance")) {
                Picker(prefs.t("Оформление", "Appearance"), selection: $prefs.theme) { Text(prefs.t("Система", "System")).tag("system"); Text(prefs.t("Светлое", "Light")).tag("light"); Text(prefs.t("Тёмное", "Dark")).tag("dark") }.pickerStyle(.segmented).labelsHidden()
            }
            Text(prefs.t("Настройки сохраняются автоматически", "Settings are saved automatically")).font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(24).frame(width: 420).preferredColorScheme(prefs.colorScheme)
    }
    private func setting<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 100, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            content().frame(maxWidth: .infinity)
        }
    }
}

private struct AccountsPopover: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var removing: AppleAccount?
    @FocusState private var focus: Field?
    private enum Field { case email, password, code }
    private var verifyingCode: Bool { model.auth.phase == "verifyingCode" }
    private var busy: Bool { model.auth.phase == "preparing" || verifyingCode }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(prefs.t("Apple Account", "Apple Accounts")).font(.system(size: 15, weight: .semibold))
            if !model.accounts.isEmpty {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.accounts) { account in
                            HStack(spacing: 3) {
                                Button { model.selectedAccountID = account.id } label: {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(account.email).font(.system(size: 12)).lineLimit(1).help(account.email)
                                            Text(account.authenticated ? prefs.t("Авторизован", "Signed in") : prefs.t("Нужно войти снова", "Sign in again")).font(.system(size: 11)).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 4)
                                        Image(systemName: "checkmark").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).opacity(model.selectedAccountID == account.id ? 1 : 0)
                                    }.padding(9).contentShape(RoundedRectangle(cornerRadius: 7))
                                }.buttonStyle(.plain)
                                    .background(model.selectedAccountID == account.id ? Color.primary.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 7))
                                    .disabled(!account.authenticated)
                                    .accessibilityAddTraits(model.selectedAccountID == account.id ? [.isSelected] : [])
                                    .help(prefs.t("Использовать для следующих скачиваний", "Use for upcoming downloads"))
                                IconUtilityButton(symbol: "arrow.clockwise", label: prefs.t("Войти снова", "Sign in again")) { email = account.email; focus = .password }
                                IconUtilityButton(symbol: "minus.circle", label: prefs.t("Удалить авторизацию", "Remove authorization")) { removing = account }
                            }
                        }
                    }
                }.frame(maxHeight: 145)
                WorkspaceRule()
            }
            if model.auth.phase == "code" || verifyingCode {
                Text(prefs.t("Код подтверждения", "Verification code")).font(.system(size: 12, weight: .medium))
                Text(model.auth.email).font(.system(size: 11)).foregroundStyle(.secondary)
                TextField(prefs.t("Код с доверенного устройства", "Code from your trusted device"), text: $code).focused($focus, equals: .code).modifier(QuietInput(focused: focus == .code)).onSubmit(submitCode).disabled(verifyingCode)
                if verifyingCode {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(prefs.t("Проверяем код…", "Verifying code…")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button(prefs.t("Отменить вход", "Cancel sign-in")) { model.cancelLogin(); code = "" }.buttonStyle(UtilityButtonStyle())
                    Spacer()
                    Button(prefs.t("Подтвердить", "Verify"), action: submitCode).buttonStyle(UtilityButtonStyle(prominent: true)).disabled(verifyingCode || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Text(prefs.t("Добавить аккаунт или войти снова", "Add an account or sign in again")).font(.system(size: 12, weight: .medium))
                TextField("Apple Account", text: $email).focused($focus, equals: .email).modifier(QuietInput(focused: focus == .email)).disabled(busy)
                SecureField(prefs.t("Пароль", "Password"), text: $password).focused($focus, equals: .password).modifier(QuietInput(focused: focus == .password)).onSubmit(login).disabled(busy)
                HStack {
                    if busy { ProgressView().controlSize(.small); Text(prefs.t("Подготовка входа…", "Preparing sign-in…")).font(.system(size: 11)).foregroundStyle(.secondary) }
                    Spacer()
                    Button(prefs.t("Войти", "Sign in"), action: login).buttonStyle(UtilityButtonStyle(prominent: true)).disabled(busy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                }
            }
            if let message = model.auth.message {
                Text(message).font(.system(size: 11)).foregroundStyle(model.auth.phase == "failed" ? Color.orange : Color.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            Text(prefs.t("Пароль и код не записываются в журнал. IPA может потребовать этот аккаунт при запуске на iPhone.", "Passwords and verification codes are never written to activity. An IPA may require its original account when launched on iPhone."))
                .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(24).frame(width: 410).preferredColorScheme(prefs.colorScheme)
        .onAppear { if model.auth.phase == "code" { focus = .code } }
        .onChange(of: model.auth.phase) { _, phase in if phase == "code" { focus = .code }; if phase == "success" { password = ""; code = "" } }
        .onDisappear { password = ""; code = "" }
        .alert(prefs.t("Удалить локальную авторизацию?", "Remove local authorization?"), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(prefs.t("Отмена", "Cancel"), role: .cancel) { removing = nil }
            Button(prefs.t("Удалить", "Remove"), role: .destructive) { if let removing { model.removeAccount(removing) }; removing = nil }
        } message: { Text((removing?.email ?? "") + "\n" + prefs.t("Сохранённые IPA останутся в библиотеке. Для скачивания потребуется войти снова.", "Saved IPA files remain in the library. Sign in again to download apps.")) }
    }
    private func login() { guard !busy, !email.isEmpty, !password.isEmpty else { return }; model.beginLogin(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password); password = "" }
    private func submitCode() { let value = code.trimmingCharacters(in: .whitespacesAndNewlines); guard !verifyingCode, !value.isEmpty else { return }; model.submitCode(value); code = "" }
}

private struct ActivityView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(prefs.t("Журнал действий", "Activity")).font(.system(size: 16, weight: .semibold))
                Spacer()
                WorkspaceSearchField(text: $search, prompt: prefs.t("Найти действие", "Find activity"), clearLabel: prefs.t("Очистить поиск", "Clear search")).frame(width: 260)
            }.padding(20)
            WorkspaceRule()
            if model.activity.isEmpty {
                WorkspaceEmptyState(symbol: "clock.arrow.circlepath", title: prefs.t("Здесь появится история", "Your activity appears here"), message: prefs.t("Скачивания, установки и ошибки сохраняются на этом Mac. Пароли и коды подтверждения в журнал не попадают.", "Downloads, installations, and errors are recorded on this Mac. Passwords and verification codes are never included."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredActivity) { entry in
                            HStack(alignment: .top, spacing: 13) {
                                Image(systemName: entry.stage == .failed ? "exclamationmark.triangle" : entry.stage == .succeeded ? "checkmark.circle" : "arrow.right.circle").foregroundStyle(entry.stage == .failed ? Color.orange : Color.secondary).frame(width: 18)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack { Text(entry.appName).fontWeight(.medium); Text(entry.version).foregroundStyle(.secondary); Spacer(); Text(entry.date, format: .dateTime.day().month().hour().minute()).foregroundStyle(.secondary).font(.system(size: 10.5)) }
                                    Text(entry.source + " → " + entry.target).foregroundStyle(.secondary)
                                    if let email = entry.accountEmail { Text(email).foregroundStyle(.secondary).textSelection(.enabled) }
                                    HStack(alignment: .top) {
                                        Text(prefs.stageTitle(entry.stage)).foregroundStyle(entry.stage == .failed ? Color.orange : Color.secondary)
                                        if let message = entry.message, !message.isEmpty { Text("· " + prefs.localizedMessage(message)).foregroundStyle(.secondary).textSelection(.enabled) }
                                    }
                                }
                            }.font(.system(size: 12)).padding(.vertical, 15).padding(.horizontal, 22)
                        }
                        if filteredActivity.isEmpty { Text(prefs.t("Ничего не найдено", "No matching activity")).foregroundStyle(.secondary).padding(30) }
                    }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var filteredActivity: [ActivityEntry] { model.activity.filter { search.isEmpty || $0.appName.localizedCaseInsensitiveContains(search) || $0.source.localizedCaseInsensitiveContains(search) || $0.target.localizedCaseInsensitiveContains(search) || ($0.accountEmail?.localizedCaseInsensitiveContains(search) ?? false) } }
}
