import AppKit
import SwiftUI
import UserNotifications
import MacPulseCore

@MainActor
final class OpenCodeAlertManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = OpenCodeAlertManager()

    private var toastPanel: NSPanel?
    private var autoDismissWorkItem: DispatchWorkItem?
    private var didRequestNotificationAuth = false

    private override init() {
        super.init()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    func requestNotificationPermissionIfNeeded() {
        guard !didRequestNotificationAuth, Bundle.main.bundleIdentifier != nil else { return }
        didRequestNotificationAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func deliverAlert(for event: OpenCodeCompletionEvent, config: OpenCodeNotifyConfig) {
        if config.playSound, !config.soundName.isEmpty {
            NSSound(named: NSSound.Name(config.soundName))?.play()
        }

        if config.showFloatingBanner {
            showFloatingHudToast(for: event, avoidTopRightOverlap: config.showSystemNotification)
        }

        if config.showSystemNotification {
            postSystemNotification(for: event, includeSound: !config.playSound)
        }
    }

    func playPreviewSound(_ soundName: String) {
        guard !soundName.isEmpty else { return }
        NSSound(named: NSSound.Name(soundName))?.play()
    }

    func dismissToast() {
        autoDismissWorkItem?.cancel()
        autoDismissWorkItem = nil
        if let existing = toastPanel {
            existing.orderOut(nil)
            existing.close()
            toastPanel = nil
        }
    }

    func focusOpenCodeHostApp() {
        let preferredBundles = [
            "dev.warp.Warp-Stable",
            "ai.opencode.desktop",
            "com.opencode.app",
            "com.googlecode.iterm2",
            "com.apple.Terminal",
            "com.google.antigravity",
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92"
        ]
        let running = NSWorkspace.shared.runningApplications
        for bid in preferredBundles {
            if let app = running.first(where: { $0.bundleIdentifier == bid }) {
                app.activate(options: [.activateAllWindows])
                return
            }
        }
    }

    // MARK: - Floating Non-Activating Sci-Fi HUD Toast (Fresh NSPanel Every Alert)
    private func showFloatingHudToast(for event: OpenCodeCompletionEvent, avoidTopRightOverlap: Bool) {
        dismissToast()

        let contentView = OpenCodeFloatingToastView(
            event: event,
            onOpen: { [weak self] in
                self?.dismissToast()
                self?.focusOpenCodeHostApp()
            },
            onDismiss: { [weak self] in
                self?.dismissToast()
            }
        )

        let width: CGFloat = 376
        let height: CGFloat = event.promptSummary != nil ? 108 : 94
        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting

        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        if let screen = targetScreen {
            let vf = screen.visibleFrame
            let yPos: CGFloat = avoidTopRightOverlap
                ? (vf.minY + 20)              // Bottom-right when macOS Notification Center is also enabled
                : (vf.maxY - height - 16)     // Top-right when HUD toast is primary
            let origin = NSPoint(
                x: vf.maxX - width - 16,
                y: yPos
            )
            panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
        }

        toastPanel = panel
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak self] in
            self?.dismissToast()
        }
        autoDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 9.0, execute: work)
    }

    // MARK: - Native macOS Notification Center
    private func postSystemNotification(for event: OpenCodeCompletionEvent, includeSound: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        requestNotificationPermissionIfNeeded()

        let content = UNMutableNotificationContent()
        let durationText = OpenCodeMonitor.formatDuration(seconds: event.durationSeconds)
        let modePrefix = event.modeLabel.map { "\($0) " } ?? ""
        content.title = "OpenCode \(modePrefix)\(event.outcome.displayLabel) • \(durationText)"
        content.subtitle = "\(event.projectName) — \(event.title)"
        content.body = event.promptSummary ?? event.title
        if includeSound {
            content.sound = .default
        }

        let req = UNNotificationRequest(
            identifier: "opencode-\(event.id.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    // MARK: - UNUserNotificationCenterDelegate
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            OpenCodeAlertManager.shared.focusOpenCodeHostApp()
        }
        completionHandler()
    }
}

private struct OpenCodeFloatingToastView: View {
    let event: OpenCodeCompletionEvent
    let onOpen: () -> Void
    let onDismiss: () -> Void

    private var accentColor: Color {
        switch event.outcome {
        case .succeeded, .unknown:
            return event.modeLabel == "PLAN" ? HudTheme.violet : HudTheme.emerald
        case .failed:
            return HudTheme.crimson
        case .interrupted:
            return HudTheme.amber
        }
    }

    private var statusIcon: String {
        switch event.outcome {
        case .succeeded, .unknown:
            return event.modeLabel == "PLAN" ? "doc.text.magnifyingglass" : "checkmark.seal.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .interrupted:
            return "stop.circle.fill"
        }
    }

    private var headerTitle: String {
        if let mode = event.modeLabel {
            return "OPENCODE \(mode) \(event.outcome.displayLabel.uppercased())"
        }
        return "OPENCODE \(event.outcome.displayLabel.uppercased())"
    }

    var body: some View {
        let height: CGFloat = event.promptSummary != nil ? 108 : 94
        return HStack(spacing: 10) {
            ZStack {
                ChamferedRect(cut: 6, cornerRadius: 3)
                    .fill(accentColor.opacity(0.22))
                    .overlay(ChamferedRect(cut: 6, cornerRadius: 3).strokeBorder(accentColor.opacity(0.75), lineWidth: 1))
                    .frame(width: 36, height: 36)
                Image(systemName: statusIcon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(headerTitle)
                        .font(.system(size: 10.5, weight: .black, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(accentColor)
                    if event.durationSeconds >= 1 {
                        Text(OpenCodeMonitor.formatDuration(seconds: event.durationSeconds))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(HudTheme.insetBg, in: Capsule())
                            .foregroundStyle(HudTheme.textSecondary)
                    }
                }

                Text(event.title)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(HudTheme.textPrimary)
                    .lineLimit(1)

                if let prompt = event.promptSummary, !prompt.isEmpty {
                    Text("“\(prompt)”")
                        .font(.system(size: 10))
                        .foregroundStyle(HudTheme.textSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(event.projectName)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HudTheme.cyan)
                        .lineLimit(1)
                    Spacer()
                    Button(action: onOpen) {
                        Text("Mở OpenCode ↗")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(HudTheme.textPrimary)
                            .padding(.horizontal, 7.5)
                            .padding(.vertical, 2.5)
                            .background(accentColor.opacity(0.26), in: Capsule())
                            .overlay(Capsule().strokeBorder(accentColor.opacity(0.75), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(HudTheme.textSecondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 376, height: height)
        .background(
            ChamferedRect(cut: 10, cornerRadius: 5)
                .fill(HudTheme.bgMid.opacity(0.98))
        )
        .overlay(
            ChamferedRect(cut: 10, cornerRadius: 5)
                .strokeBorder(accentColor.opacity(0.85), lineWidth: 1.3)
        )
        .overlay(
            HudCornerBracketsShape(length: 9)
                .stroke(accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
                .allowsHitTesting(false)
        )
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }
}
