import SwiftUI
import CRCLIEngine

class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = EngineService()
    let hotkey = HotkeyService()
    let overlay = OverlayService()
    let permissions = PermissionService()
    let downloads = ModelDownloadService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await startApp() }
    }

    @MainActor
    private func startApp() async {
        overlay.initialize()
        permissions.startPolling()

        let modelsDir = NSString(string: "~/Library/RCLI/models").expandingTildeInPath
        do {
            try await engine.initialize(modelsDir: modelsDir, gpuLayers: 99)
        } catch {
            return
        }

        if permissions.accessibilityGranted {
            setupHotkey()
        }
    }

    @MainActor
    func setupHotkey() {
        hotkey.onHotkeyPressed = { [engine, hotkey, overlay] in
            Task { @MainActor in
                if hotkey.isRecording {
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

@main
struct RobinApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.engine)
                .environment(appDelegate.hotkey)
                .environment(appDelegate.overlay)
                .environment(appDelegate.permissions)
                .environment(appDelegate.downloads)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Window("Welcome to RCLI", id: "onboarding") {
            OnboardingView(isPresented: Binding(
                get: { !hasCompletedOnboarding },
                set: { newValue in
                    if !newValue { hasCompletedOnboarding = true }
                }
            ))
            .environment(appDelegate.engine)
            .environment(appDelegate.permissions)
            .environment(appDelegate.downloads)
        }
        .defaultSize(width: 560, height: 420)
        .windowResizability(.contentSize)

        Window("RCLI", id: "panel") {
            PanelView()
                .environment(appDelegate.engine)
        }
        .defaultSize(width: 420, height: 600)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(appDelegate.engine)
                .environment(appDelegate.hotkey)
                .environment(appDelegate.permissions)
                .environment(appDelegate.downloads)
        }
    }

    private var menuBarIcon: String {
        switch appDelegate.engine.lifecycleState {
        case .loading: return "circle.dashed"
        case .ready:
            switch appDelegate.engine.pipelineState {
            case .listening: return "waveform"
            case .processing, .speaking: return "bolt.fill"
            default: return "waveform"
            }
        case .error: return "exclamationmark.triangle"
        }
    }
}
