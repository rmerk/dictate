import Foundation
import Observation
import CRCLIEngine

@MainActor
@Observable
final class HotkeyService {
    var isListening: Bool = false
    var isRecording: Bool = false
    var hotkeyString: String = "cmd+j"
    /// Set to true when the user explicitly stops the listener via the toggle,
    /// preventing the accessibility observer from auto-restarting it.
    var userDisabled: Bool = false

    var onHotkeyPressed: (() -> Void)?

    init() {
        if let saved = ConfigService.shared.read(key: "hotkey"), !saved.isEmpty {
            hotkeyString = saved
        }
    }

    func start() -> Bool {
        // Stop any existing listener before registering a new one to prevent
        // multiple CGEventTaps from being registered simultaneously.
        if isListening { stop() }
        userDisabled = false
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        let result = rcli_hotkey_start(hotkeyString, Self.hotkeyTrampoline, ptr)
        isListening = (result != 0)
        return isListening
    }

    func stop() {
        rcli_hotkey_stop()
        isListening = false
        userDisabled = true
    }

    func restart(with newHotkey: String) -> Bool {
        let wasListening = isListening
        stop()
        hotkeyString = newHotkey
        do {
            try ConfigService.shared.write(key: "hotkey", value: newHotkey)
        } catch {
            print("[HotkeyService] Failed to persist hotkey: \(error)")
        }
        return wasListening ? start() : false
    }

    func setRecording(_ active: Bool) {
        isRecording = active
        rcli_hotkey_set_active(active ? 1 : 0)
    }

    static func checkAccessibility() -> Bool {
        rcli_hotkey_check_accessibility() != 0
    }

    private static let hotkeyTrampoline: RCLIHotkeyCallback = { userData in
        guard let userData else { return }
        let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
        Task { @MainActor in
            service.onHotkeyPressed?()
        }
    }
}
