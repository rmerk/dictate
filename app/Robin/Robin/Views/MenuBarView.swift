import SwiftUI

struct MenuBarView: View {
    @Environment(EngineService.self) private var engine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status row
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.headline)
                Spacer()
            }

            Divider()

            // Quit
            Button("Quit Robin") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 260)
    }

    private var statusColor: Color {
        switch engine.lifecycleState {
        case .loading: return .orange
        case .ready: return .green
        case .error: return .red
        }
    }

    private var statusText: String {
        switch engine.lifecycleState {
        case .loading: return "Starting up..."
        case .ready: return "Ready"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
