import SwiftUI

struct MenuBarView: View {
    @Environment(EngineService.self) private var engine
    @Environment(HotkeyService.self) private var hotkey
    @Environment(PermissionService.self) private var permissions
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.headline)
                Spacer()
                if case .ready = engine.lifecycleState {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(engine.primaryStatusModelLine)
                            .font(.caption)
                        if let secondaryLine = engine.secondaryStatusModelLine {
                            Text(secondaryLine)
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                }
            }

            // Permission warnings
            if !permissions.microphoneGranted {
                PermissionBanner(
                    message: "Microphone access needed",
                    action: { Task { await permissions.requestMicrophone() } }
                )
            }
            if !permissions.accessibilityGranted {
                PermissionBanner(
                    message: "Accessibility needed for hotkey",
                    action: { permissions.requestAccessibility() }
                )
            }

            if case .ready = engine.lifecycleState {
                Divider()

                // Quick actions
                HStack(spacing: 8) {
                    QuickActionCard(
                        icon: "mic.fill",
                        label: "Dictation",
                        shortcut: HotkeyFormatter.displayString(for: hotkey.hotkeyString),
                        enabled: permissions.microphoneGranted && permissions.accessibilityGranted,
                        action: { hotkey.onHotkeyPressed?() }
                    )
                    QuickActionCard(
                        icon: "bolt.fill",
                        label: "Command",
                        shortcut: HotkeyFormatter.displayString(for: hotkey.commandHotkeyString),
                        enabled: permissions.microphoneGranted && permissions.accessibilityGranted,
                        action: { hotkey.onCommandHotkeyPressed?() }
                    )
                    QuickActionCard(
                        icon: "text.bubble",
                        label: "Panel",
                        shortcut: "",
                        enabled: true,
                        action: { openWindow(id: "panel") }
                    )
                }
            }

            Divider()

            Button("Settings...") {
                SettingsWindowCoordinator.presentSettings {
                    openSettings()
                }
            }
            .buttonStyle(.plain)

            Button("Quit Robin") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(width: 280)
        .task {
            if !hasCompletedOnboarding {
                openWindow(id: "onboarding")
            }
        }
    }

    private var statusColor: Color {
        switch engine.lifecycleState {
        case .loading: return .orange
        case .ready: return .green
        case .error: return .red
        }
    }

    private var statusText: String {
        switch engine.lifecycleState {
        case .loading: return "Starting up..."
        case .ready:
            switch engine.pipelineState {
            case .idle: return "Ready"
            case .listening: return "Listening..."
            case .processing: return "Processing..."
            case .speaking: return "Speaking..."
            case .interrupted: return "Interrupted"
            }
        case .error(let msg): return msg
        }
    }
}

// MARK: - Supporting Views

struct PermissionBanner: View {
    let message: String
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
            Spacer()
            Button("Grant") { action() }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(8)
        .background(.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

struct QuickActionCard: View {
    let icon: String
    let label: String
    let shortcut: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption)
                if !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(.vertical, 8)
            .background(.quaternary)
            .cornerRadius(8)
            .opacity(enabled ? 1.0 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
