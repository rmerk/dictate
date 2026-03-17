import SwiftUI

@main
struct RobinApp: App {
    @State private var engine = EngineService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(engine)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        switch engine.lifecycleState {
        case .loading: return "circle.dashed"
        case .ready: return "waveform"
        case .error: return "exclamationmark.triangle"
        }
    }
}
