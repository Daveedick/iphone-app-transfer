import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// NSString providers advertise UTF-8 directly. Include the exact identifier
/// rather than relying on the host's UTI conformance registry for parent types.
let AppTransferDragTypes: [UTType] = [.utf8PlainText, .plainText, .text]

/// The translucent surface samples the desktop, never the opacity of text or controls.
struct FrostedWorkspaceBackground: NSViewRepresentable {
    var reducedTransparency: Bool
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = reducedTransparency ? .windowBackground : .underWindowBackground
    }
}

/// Configure only the containing window; standard macOS corners and traffic lights remain native.
struct NativeWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowProbe() }
    func updateNSView(_ view: NSView, context: Context) {}
    private final class WindowProbe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = false
        }
    }
}

struct UtilityButtonStyle: ButtonStyle {
    var prominent = false
    var borderless = false

    func makeBody(configuration: Configuration) -> some View {
        UtilityButtonSurface(configuration: configuration, prominent: prominent, borderless: borderless)
    }
}

/// Toolbar controls rest on the workspace. Filled controls are reserved for
/// actions that need a persistent affordance, and accent for the primary action.
private struct UtilityButtonSurface: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let borderless: Bool
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    private var background: Color {
        if prominent && enabled { return .accentColor }
        let resting = borderless ? 0 : (scheme == .dark ? 0.075 : 0.055)
        let hovered = scheme == .dark ? 0.11 : 0.075
        let pressed = scheme == .dark ? 0.16 : 0.12
        let opacity = !enabled ? resting * 0.65 : configuration.isPressed ? pressed : self.hovered ? hovered : resting
        return Color.primary.opacity(opacity + (contrast == .increased && !borderless ? 0.035 : 0))
    }

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .foregroundStyle(!enabled ? Color.secondary : prominent ? Color(nsColor: .selectedControlTextColor) : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(background)
                    .overlay {
                        if prominent && enabled {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.black.opacity(configuration.isPressed ? 0.12 : hovered ? 0.05 : 0))
                        }
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
    }
}

struct IconUtilityButton: View {
    let symbol: String
    let label: String
    var borderless = true
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 19, height: 18) }
            .buttonStyle(UtilityButtonStyle(borderless: borderless))
            .help(label).accessibilityLabel(label)
    }
}

struct AppArtwork: View {
    var image: NSImage?
    var size: CGFloat = 30
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().interpolation(.high).scaledToFit() }
            else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.065))
                    .overlay { Image(systemName: "app.dashed").font(.system(size: size * 0.57)).foregroundStyle(.secondary) }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct WorkspaceSearchField: View {
    @Binding var text: String
    let prompt: String
    var clearLabel = "Clear search"
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.system(size: 12))
                .focused($focused)
                .focusEffectDisabled()
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 9).frame(height: 30)
        .background(Color.primary.opacity(scheme == .dark ? 0.055 : 0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.46 : 0.24), lineWidth: 1)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: focused)
    }
}

struct WorkspaceEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(26).frame(maxWidth: 390).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AppListRow: View {
    let name: String
    let detail: String
    var image: NSImage?
    var selected: Bool
    var comfortable: Bool
    var symbol: String?
    var warning: Bool = false
    var keyboardFocused: Bool = false
    var accessibilitySelect: () -> Void = {}
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    @Environment(\.controlActiveState) private var activeState

    private var rowFill: Color {
        if selected {
            let active = scheme == .dark ? 0.13 : 0.085
            let inactive = scheme == .dark ? 0.08 : 0.055
            return Color.primary.opacity((activeState == .inactive ? inactive : active) + (contrast == .increased ? 0.055 : 0))
        }
        return Color.primary.opacity(hovered ? (scheme == .dark ? 0.055 : 0.035) : 0)
    }

    var body: some View {
        HStack(spacing: 9) {
            AppArtwork(image: image, size: comfortable ? 30 : 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 12.5, weight: .regular)).lineLimit(1)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 2)
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(warning ? Color.orange : Color.secondary)
            }
        }
        .padding(.horizontal, 8).frame(height: comfortable ? 57 : 46)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowFill)
        }
        .overlay {
            if keyboardFocused && activeState != .inactive {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.28), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name + ", " + detail))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityAction { accessibilitySelect() }
    }
}

/// Drop strings contain only our versioned identifiers; the model validates every payload.
struct TextPayloadDropDelegate: DropDelegate {
    let receive: (String) -> Void
    var hover: ((Bool) -> Void)?
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: AppTransferDragTypes) }
    func dropEntered(info: DropInfo) { hover?(true) }
    func dropExited(info: DropInfo) { hover?(false) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }
    func performDrop(info: DropInfo) -> Bool {
        hover?(false)
        guard let provider = info.itemProviders(for: AppTransferDragTypes).first else { return false }
        _ = provider.loadObject(ofClass: String.self) { text, _ in
            guard let text else { return }
            DispatchQueue.main.async { receive(text) }
        }
        return true
    }
}

struct EdgeScrollDropDelegate: DropDelegate {
    var entered: () -> Void
    var exited: () -> Void
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: AppTransferDragTypes) }
    func dropEntered(info: DropInfo) { entered() }
    func dropExited(info: DropInfo) { exited() }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .cancel) }
    func performDrop(info: DropInfo) -> Bool { exited(); return false }
}

func readableBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
