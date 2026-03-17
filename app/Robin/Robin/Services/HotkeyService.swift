import Foundation
import Observation
import CRCLIEngine

@MainActor
@Observable
final class HotkeyService {
    var isListening: Bool = false
    var isRecording: Bool = false
    var hotkeyString: String = "cmd+j"

    var onHotkeyPressed: (() -> Void)?

    func start() -> Bool {
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        let result = rcli_hotkey_start(hotkeyString, Self.hotkeyTrampoline, ptr)
        isListening = (result != 0)
        return isListening
    }

    func stop() {
        rcli_hotkey_stop()
        isListening = false
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
