import SwiftUI
import CRCLIEngine

@main
struct RobinApp: App {
    @State private var engine = EngineService()
    @State private var hotkey = HotkeyService()
    @State private var overlay = OverlayService()
    @State private var permissions = PermissionService()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(engine)
                .environment(hotkey)
                .environment(overlay)
                .environment(permissions)
                .task { await startApp() }
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView(isPresented: $showOnboarding)
                        .environment(engine)
                        .environment(permissions)
                        .onDisappear { hasCompletedOnboarding = true }
                }
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Window("RCLI", id: "panel") {
            PanelView()
                .environment(engine)
        }
        .defaultSize(width: 420, height: 600)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(engine)
                .environment(hotkey)
                .environment(permissions)
        }
    }

    private var menuBarIcon: String {
        switch engine.lifecycleState {
        case .loading: return "circle.dashed"
        case .ready:
            switch engine.pipelineState {
            case .listening: return "waveform"
            case .processing, .speaking: return "bolt.fill"
            default: return "waveform"
            }
        case .error: return "exclamationmark.triangle"
        }
    }

    private func startApp() async {
        // Show onboarding on first launch
        if !hasCompletedOnboarding {
            showOnboarding = true
        }

        // Initialize overlay
        overlay.initialize()

        // Start permission polling
        permissions.startPolling()

        // Initialize engine
        let modelsDir = NSString(string: "~/Library/RCLI/models").expandingTildeInPath
        do {
            try await engine.initialize(modelsDir: modelsDir, gpuLayers: 99)
        } catch {
            return // lifecycleState is already .error
        }

        // Start hotkey if accessibility granted
        if permissions.accessibilityGranted {
            setupHotkey()
        }
    }

    private func setupHotkey() {
        hotkey.onHotkeyPressed = { [engine, hotkey, overlay] in
            Task { @MainActor in
                if hotkey.isRecording {
                    // Stop recording
                    hotkey.setRecording(false)
                    overlay.setState(.transcribing)

                    do {
                        let text = try await engine.stopAndTranscribe()
                        if !text.isEmpty {
                            rcli_paste_text(text)
                        }
                    } catch {
                        // Transcription failed — just dismiss
                    }
                    overlay.dismiss()
                } else {
                    // Start recording
                    var caretX: Double = 0
                    var caretY: Double = 0
                    let hasCaret = rcli_get_caret_position(&caretX, &caretY)

                    if hasCaret == 0 {
                        overlay.show(state: .recording, caretX: caretX, caretY: caretY)
                    } else {
                        overlay.show(state: .recording)
                    }

                    engine.startCapture()
                    hotkey.setRecording(true)
                }
            }
        }
        _ = hotkey.start()
    }
}
