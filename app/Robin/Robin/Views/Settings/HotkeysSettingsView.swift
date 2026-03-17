import SwiftUI

struct HotkeysSettingsView: View {
    @Environment(HotkeyService.self) private var hotkey
    @Environment(\.hotkeySetup) private var hotkeySetup

    var body: some View {
        Form {
            Section("Dictation") {
                HStack {
                    Text("Dictation hotkey")
                    Spacer()
                    HotkeyRecorder()
                }
                Text("Click the shortcut to change it. At least one modifier (⌘, ⌥, ⌃, ⇧) is required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                HStack {
                    Text("Hotkey listener")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { hotkey.isListening },
                        set: { newValue in
                            if newValue {
                                // Use the setup action to ensure onHotkeyPressed is wired
                                // before starting the C-level listener.
                                hotkeySetup()
                            } else {
                                hotkey.stop()
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
// MARK: - Environment Key

private struct HotkeySetupKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var hotkeySetup: () -> Void {
        get { self[HotkeySetupKey.self] }
        set { self[HotkeySetupKey.self] = newValue }
    }
}

