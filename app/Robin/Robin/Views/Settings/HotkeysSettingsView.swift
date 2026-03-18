import SwiftUI

struct HotkeysSettingsView: View {
    @Environment(HotkeyService.self) private var hotkey
    @Environment(\.hotkeySetup) private var hotkeySetup
    @AppStorage("hotkeyRoutingMode") private var routingModeRaw = "manual"

    private var isAutoRouting: Bool { routingModeRaw == "auto" }

    var body: some View {
        Form {
            Section("Dictation") {
                HStack {
                    Text("Dictation hotkey")
                    Spacer()
                    HotkeyRecorder(target: .dictation)
                }
                Text("Voice → text, pasted at the cursor. Use this for writing, notes, and messages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Command") {
                HStack {
                    Text("Command hotkey")
                    Spacer()
                    HotkeyRecorder(target: .command)
                }
                Text("Voice → LLM + actions (e.g. \"open Safari\", \"create a note\"). Response appears in the conversation panel, not at the cursor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Routing") {
                Toggle("Auto-detect mode", isOn: Binding(
                    get: { isAutoRouting },
                    set: { routingModeRaw = $0 ? "auto" : "manual" }
                ))
                if isAutoRouting {
                    Text("One hotkey does both: command verbs (\"open Safari\", \"create a note\") run LLM + actions; everything else is pasted as dictation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Dictation hotkey always pastes. Command hotkey always runs LLM + actions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

