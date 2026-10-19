import AppKit
import SwiftUI
import AppTransferCore

/// Presentation order is independent of the coordinator's FIFO work order.
struct TransferQueuePanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    let maximumBodyHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var scale
    @State private var resizeHovered = false
    @State private var resizeOrigin: CGFloat?
    @State private var dragHeight: CGFloat?
    @FocusState private var resizeFocused: Bool

    private var height: CGFloat { bounded(dragHeight ?? CGFloat(prefs.queueBodyHeight)) }
    private var jobs: [TransferJob] { model.displayedJobs }
    private var latestSummary: TransferJob? {
        model.jobs.first { [.resolving, .downloading, .validating, .uploading, .installing, .verifying].contains($0.stage) }
            ?? jobs.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if prefs.queueVisible { resizeHandle }
            else { rule }
            header
            if prefs.queueVisible {
                queueList.frame(height: height)
            }
        }
    }

    private var rule: some View {
        Rectangle().fill(Color.primary.opacity(contrast == .increased ? 0.3 : 0.09))
            .frame(height: 1 / scale).accessibilityHidden(true)
    }

    private var resizeHandle: some View {
        ZStack {
            QueueResizeHandle(onHover: { resizeHovered = $0 }, onBegin: {
                resizeOrigin = height
                resizeFocused = true
            }, onChange: { delta in
                dragHeight = bounded((resizeOrigin ?? height) + delta)
            }, onEnd: {
                prefs.queueBodyHeight = Double(height)
                resizeOrigin = nil; dragHeight = nil
            })
            rule.allowsHitTesting(false)
            Capsule().fill(Color.primary.opacity(resizeHovered || resizeFocused || dragHeight != nil ? 0.42 : 0.18))
                .frame(width: 40, height: 3).allowsHitTesting(false)
        }
        .frame(height: QueueResizeHandle.height)
        .focusable().focusEffectDisabled().focused($resizeFocused)
        .onKeyPress(.upArrow) { changeHeight(by: 24); return .handled }
        .onKeyPress(.downArrow) { changeHeight(by: -24); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(prefs.t("Высота очереди", "Queue height"))
        .accessibilityValue(prefs.t("\(Int(height)) пунктов", "\(Int(height)) points"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: changeHeight(by: 24)
            case .decrement: changeHeight(by: -24)
            @unknown default: break
            }
        }
        .help(prefs.t("Потяните вверх или вниз, чтобы изменить высоту очереди. Клавиши ↑ и ↓ также меняют высоту.", "Drag up or down to resize the queue. The ↑ and ↓ keys also adjust its height."))
        .onDisappear { resizeHovered = false; resizeOrigin = nil; dragHeight = nil }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { prefs.queueVisible.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.number")
                    Text(prefs.t("Очередь", "Queue")).fontWeight(.medium)
                    Text("\(model.jobs.filter { !$0.stage.terminal }.count)").foregroundStyle(.secondary)
                    Image(systemName: prefs.queueVisible ? "chevron.down" : "chevron.up").font(.system(size: 9))
                }
            }.buttonStyle(.plain)
            if let feedback = model.queueFeedback {
                Text(feedback.message).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    .accessibilityIdentifier("queue-feedback")
                    .help(feedback.message)
            } else if !prefs.queueVisible, let latest = latestSummary {
                Text(latest.app.name + " · " + prefs.stageTitle(latest.stage))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if model.queuePaused { Text(prefs.t("Приостановлено", "Paused")).font(.system(size: 10.5)).foregroundStyle(.secondary) }
            Button { model.toggleQueuePaused() } label: {
                Label(model.queuePaused ? prefs.t("Продолжить", "Resume") : prefs.t("Пауза", "Pause"), systemImage: model.queuePaused ? "play" : "pause")
            }.buttonStyle(UtilityButtonStyle(borderless: true))
                .disabled(!model.queuePaused && !model.jobs.contains(where: { !$0.stage.terminal }))
        }
        .font(.system(size: 12)).padding(.horizontal, 16).frame(height: 40)
        .background(Color.primary.opacity(model.queueFeedback == nil ? 0 : 0.055))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.queueFeedback?.id)
    }

    private var queueList: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("queue-top").accessibilityHidden(true)
                    if jobs.isEmpty {
                        Text(prefs.t("Задач пока нет", "No tasks yet"))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 28)
                    }
                    ForEach(jobs) { job in
                        TransferJobRow(model: model, prefs: prefs, job: job)
                            .padding(.horizontal, 10)
                            .background(Color.primary.opacity(model.queueFeedback?.jobIDs.contains(job.id) == true ? 0.075 : 0), in: RoundedRectangle(cornerRadius: 7))
                            .id(job.id)
                    }
                }.padding(.horizontal, 6).padding(.bottom, 6)
            }
            .accessibilityLabel(prefs.t("Очередь: новые задачи сверху", "Queue: newest tasks first"))
            .task(id: model.queueFeedback?.id) {
                guard let feedback = model.queueFeedback else { return }
                // Wait for the newly accepted row to enter the SwiftUI tree.
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    reader.scrollTo(feedback.focusJobID, anchor: .top)
                }
            }
        }
    }

    private func bounded(_ value: CGFloat) -> CGFloat {
        min(min(900, max(80, maximumBodyHeight)), max(80, value))
    }
    private func changeHeight(by delta: CGFloat) {
        prefs.queueBodyHeight = Double(bounded(height + delta))
    }
}
