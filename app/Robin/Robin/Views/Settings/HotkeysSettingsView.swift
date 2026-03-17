import SwiftUI

struct HotkeysSettingsView: View {
    @Environment(HotkeyService.self) private var hotkey
    @State private var dictationHotkey = "⌘J"

    var body: some View {
        Form {
            Section("Dictation") {
                HStack {
                    Text("Dictation hotkey")
                    Spacer()
                    Text(dictationHotkey)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.quaternary)
                        .cornerRadius(6)
                        .font(.system(.body, design: .monospaced))
                }
                Text("⌘J is also used by Safari for Downloads. Choose a different shortcut if this conflicts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                HStack {
                    Text("Hotkey listener")
                    Spacer()
                    Image(systemName: hotkey.isListening ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(hotkey.isListening ? .green : .red)
                    Text(hotkey.isListening ? "Active" : "Inactive")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
