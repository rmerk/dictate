import SwiftUI

@main
struct RCLIApp: App {
    @State private var engine = EngineService()

    var body: some Scene {
        MenuBarExtra("RCLI", systemImage: menuBarIcon) {
            MenuBarView()
                .environment(engine)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        switch engine.lifecycleState {
        case .loading: return "circle.dotted"
        case .ready: return "waveform"
        case .error: return "exclamationmark.triangle"
        }
    }
}
