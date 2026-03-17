import Foundation
import Observation
import CRCLIEngine

@MainActor
@Observable
final class OverlayService {
    private var initialized = false

    func initialize() {
        guard !initialized else { return }
        rcli_overlay_init()
        initialized = true
    }

    func show(state: OverlayState, caretX: Double? = nil, caretY: Double? = nil) {
        let stateInt: Int32 = (state == .recording) ? RCLI_OVERLAY_RECORDING : RCLI_OVERLAY_TRANSCRIBING
        if let x = caretX, let y = caretY {
            rcli_overlay_show(stateInt, x, y, 1)
        } else {
            rcli_overlay_show(stateInt, 0, 0, 0)
        }
    }

    func setState(_ state: OverlayState) {
        let stateInt: Int32 = (state == .recording) ? RCLI_OVERLAY_RECORDING : RCLI_OVERLAY_TRANSCRIBING
        rcli_overlay_set_state(stateInt)
    }

    func dismiss() {
        rcli_overlay_dismiss()
    }

    func cleanup() {
        rcli_overlay_cleanup()
        initialized = false
    }

    enum OverlayState {
        case recording
        case transcribing
    }
}
