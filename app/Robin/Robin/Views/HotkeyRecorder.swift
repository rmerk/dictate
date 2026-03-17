import SwiftUI
import Carbon.HIToolbox

// MARK: - Formatting

enum HotkeyFormatter {
    static func displayString(for hotkeyStr: String) -> String {
        let parts = hotkeyStr.lowercased().split(separator: "+").map(String.init)
        var result = ""
        for part in parts {
            switch part {
            case "cmd", "command", "meta": result += "⌘"
            case "ctrl", "control":        result += "⌃"
            case "alt", "option", "opt":   result += "⌥"
            case "shift":                  result += "⇧"
            default:                       result += part.uppercased()
            }
        }
        return result
    }

    static func buildHotkeyString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String? {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option)  { parts.append("alt") }
        if modifiers.contains(.shift)   { parts.append("shift") }

        guard let keyName = keyCodeNames[Int(keyCode)] else { return nil }
        parts.append(keyName)
        return parts.joined(separator: "+")
    }

    static let keyCodeNames: [Int: String] = [
        kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c",
        kVK_ANSI_D: "d", kVK_ANSI_E: "e", kVK_ANSI_F: "f",
        kVK_ANSI_G: "g", kVK_ANSI_H: "h", kVK_ANSI_I: "i",
        kVK_ANSI_J: "j", kVK_ANSI_K: "k", kVK_ANSI_L: "l",
        kVK_ANSI_M: "m", kVK_ANSI_N: "n", kVK_ANSI_O: "o",
        kVK_ANSI_P: "p", kVK_ANSI_Q: "q", kVK_ANSI_R: "r",
        kVK_ANSI_S: "s", kVK_ANSI_T: "t", kVK_ANSI_U: "u",
        kVK_ANSI_V: "v", kVK_ANSI_W: "w", kVK_ANSI_X: "x",
        kVK_ANSI_Y: "y", kVK_ANSI_Z: "z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2",
        kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5",
        kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
        kVK_ANSI_9: "9",
        kVK_Space: "space", kVK_Return: "return", kVK_Tab: "tab",
        kVK_Escape: "escape", kVK_Delete: "delete",
        kVK_F1: "f1", kVK_F2: "f2", kVK_F3: "f3",
        kVK_F4: "f4", kVK_F5: "f5", kVK_F6: "f6",
        kVK_F7: "f7", kVK_F8: "f8", kVK_F9: "f9",
        kVK_F10: "f10", kVK_F11: "f11", kVK_F12: "f12",
    ]
}

// MARK: - Reusable recorder view

enum HotkeyRecorderTarget {
    case dictation
    case command
}

struct HotkeyRecorder: View {
    @Environment(HotkeyService.self) private var hotkey
    var target: HotkeyRecorderTarget = .dictation
    var font: Font = .system(.body, design: .monospaced)
    var padding: CGFloat = 12

    @State private var isCapturing = false
    @State private var monitor: Any?

    private var currentHotkeyString: String {
        target == .dictation ? hotkey.hotkeyString : hotkey.commandHotkeyString
    }

    var body: some View {
        Button {
            startCapture()
        } label: {
            Text(isCapturing ? "Press a shortcut…" : HotkeyFormatter.displayString(for: currentHotkeyString))
                .font(font)
                .padding(.horizontal, padding)
                .padding(.vertical, padding * 0.5)
                .background(isCapturing ? Color.accentColor.opacity(0.2) : Color(.quaternaryLabelColor))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onDisappear { stopCapture() }
    }

    private func startCapture() {
        stopCapture() // clean up any stale monitor
        isCapturing = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.type == .keyDown {
                if event.keyCode == UInt16(kVK_Escape) {
                    stopCapture()
                    return nil
                }

                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard !modifiers.intersection([.command, .option, .control, .shift]).isEmpty else {
                    return nil
                }

                if let hotkeyStr = HotkeyFormatter.buildHotkeyString(keyCode: event.keyCode, modifiers: modifiers) {
                    switch target {
                    case .dictation: _ = hotkey.restart(with: hotkeyStr)
                    case .command:   _ = hotkey.restartCommandHotkey(with: hotkeyStr)
                    }
                }
                stopCapture()
                return nil
            }
            return event
        }
    }

    private func stopCapture() {
        isCapturing = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
