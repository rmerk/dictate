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
        let stateInt = overlayStateInt(state)
        if let x = caretX, let y = caretY {
            rcli_overlay_show(stateInt, x, y, 1)
        } else {
            rcli_overlay_show(stateInt, 0, 0, 0)
        }
    }

    func setState(_ state: OverlayState) {
        rcli_overlay_set_state(overlayStateInt(state))
    }

    private func overlayStateInt(_ state: OverlayState) -> Int32 {
        switch state {
        case .recording:   return RCLI_OVERLAY_RECORDING
        case .transcribing: return RCLI_OVERLAY_TRANSCRIBING
        // Command mode reuses TRANSCRIBING state visually; the C overlay doesn't
        // have a dedicated command state, so we fall back to transcribing.
        case .commanding:  return RCLI_OVERLAY_TRANSCRIBING
        }
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
        case commanding  // command mode recording — visually distinct from dictation
    }
}
