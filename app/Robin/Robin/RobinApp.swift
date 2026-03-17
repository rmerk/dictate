import SwiftUI

@main
struct RobinApp: App {
    @State private var engine = EngineService()

    var body: some Scene {
        MenuBarExtra("Robin", systemImage: menuBarIcon) {
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
