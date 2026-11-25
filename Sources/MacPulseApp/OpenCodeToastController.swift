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
            showFloatingHudToast(for: event)
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
        toastPanel?.orderOut(nil)
    }

    func focusOpenCodeHostApp() {
        // Smart priority: activate running terminal or OpenCode host app without spawning new ones
        let preferredBundles = [
            "dev.warp.Warp-Stable",
            "ai.opencode.desktop",
            "com.opencode.app",
            "com.googlecode.iterm2",
            "com.apple.Terminal",
            "com.google.antigravity",
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92" // Cursor
        ]
        let running = NSWorkspace.shared.runningApplications
        for bid in preferredBundles {
            if let app = running.first(where: { $0.bundleIdentifier == bid }) {
                app.activate(options: [.activateAllWindows])
                return
            }
        }
    }

    // MARK: - Floating Non-Activating Sci-Fi HUD Toast
    private func showFloatingHudToast(for event: OpenCodeCompletionEvent) {
        autoDismissWorkItem?.cancel()

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

        let hosting = NSHostingView(rootView: contentView)
        let width: CGFloat = 356
        let height: CGFloat = 94
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let panel: NSPanel
        if let existing = toastPanel {
            panel = existing
            panel.contentView = hosting
        } else {
            let created = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.isFloatingPanel = true
            created.level = .floating
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = false
            created.hidesOnDeactivate = false
            created.ignoresMouseEvents = false
            created.contentView = hosting
            toastPanel = created
            panel = created
        }

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let vf = screen.visibleFrame
            let origin = NSPoint(
                x: vf.maxX - width - 16,
                y: vf.maxY - height - 16
            )
            panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
        }

        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak self] in
            self?.dismissToast()
        }
        autoDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.5, execute: work)
    }

    // MARK: - Native macOS Notification Center
    private func postSystemNotification(for event: OpenCodeCompletionEvent, includeSound: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        requestNotificationPermissionIfNeeded()

        let content = UNMutableNotificationContent()
        let durationText = OpenCodeMonitor.formatDuration(seconds: event.durationSeconds)
        content.title = "OpenCode \(event.outcome.displayLabel) • \(durationText)"
        content.subtitle = event.projectName
        content.body = event.title
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
        case .succeeded, .unknown: return HudTheme.emerald
        case .failed: return HudTheme.crimson
        case .interrupted: return HudTheme.amber
        }
    }

    private var statusIcon: String {
        switch event.outcome {
        case .succeeded, .unknown: return "checkmark.seal.fill"
        case .failed: return "xmark.octagon.fill"
        case .interrupted: return "stop.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ChamferedRect(cut: 6, cornerRadius: 3)
                    .fill(accentColor.opacity(0.22))
                    .overlay(ChamferedRect(cut: 6, cornerRadius: 3).strokeBorder(accentColor.opacity(0.7), lineWidth: 1))
                    .frame(width: 36, height: 36)
                Image(systemName: statusIcon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("OPENCODE \(event.outcome.displayLabel.uppercased())")
                        .font(.system(size: 10.5, weight: .black, design: .monospaced))
                        .tracking(0.6)
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
                    .lineLimit(2)

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
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(accentColor.opacity(0.24), in: Capsule())
                            .overlay(Capsule().strokeBorder(accentColor.opacity(0.7), lineWidth: 0.7))
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
        .frame(width: 356, height: 94)
        .background(
            ChamferedRect(cut: 10, cornerRadius: 5)
                .fill(HudTheme.bgMid.opacity(0.97))
        )
        .overlay(
            ChamferedRect(cut: 10, cornerRadius: 5)
                .strokeBorder(accentColor.opacity(0.80), lineWidth: 1.2)
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
