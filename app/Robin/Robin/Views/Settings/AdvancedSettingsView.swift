import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(PermissionService.self) private var permissions
    @State private var performanceMode = "balanced"

    var body: some View {
        Form {
            Section("Performance") {
                Picker("Mode", selection: $performanceMode) {
                    Text("Battery Saver").tag("battery")
                    Text("Balanced").tag("balanced")
                    Text("Maximum Quality").tag("quality")
                }
                .pickerStyle(.segmented)
                .onChange(of: performanceMode) { _, newValue in
                    try? ConfigService.shared.write(key: "performance_mode", value: newValue)
                }
                Text(performanceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                PermissionRow(
                    name: "Microphone",
                    granted: permissions.microphoneGranted,
                    action: { permissions.openMicrophoneSettings() }
                )
                PermissionRow(
                    name: "Accessibility",
                    granted: permissions.accessibilityGranted,
                    action: { permissions.requestAccessibility() }
                )
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            performanceMode = ConfigService.shared.read(key: "performance_mode") ?? "balanced"
        }
    }

    private var performanceDescription: String {
        switch performanceMode {
        case "battery": return "Uses fewer GPU layers. Lower quality, longer battery life."
        case "quality": return "Uses all GPU layers. Best quality, higher power usage."
        default: return "Default GPU settings. Good balance of quality and efficiency."
        }
    }
}

struct PermissionRow: View {
    let name: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Granted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Open Settings") { action() }
                    .controlSize(.small)
            }
        }
    }
}
