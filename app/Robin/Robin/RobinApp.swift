import SwiftUI
import AppKit
import CRCLIEngine

class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = EngineService()
    let hotkey = HotkeyService()
    let overlay = OverlayService()
    let permissions = PermissionService()
    let downloads = ModelDownloadService()
    let conversation = ConversationStore()

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
            engine.lifecycleState = .error(error.localizedDescription)
            return
        }

        if permissions.accessibilityGranted {
            setupHotkey()
        }
        startAccessibilityObserver()
    }

    @MainActor
    private func startAccessibilityObserver() {
        Task { @MainActor [weak self] in
            while let self {
                try? await Task.sleep(for: .seconds(3))
                let accessible = self.permissions.accessibilityGranted
                // Re-register in two cases:
                // 1. Accessibility just became granted and listener isn't running
                // 2. Listener flag says running but C-level tap is actually dead
                //    (detectable because accessibility check would still return true
                //     but we can re-verify by checking if start() was previously false)
                if accessible && !self.hotkey.isListening && !self.hotkey.userDisabled {
                    self.setupHotkey()
                }
            }
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

/// Reaches into the underlying NSWindow and sets its appearance directly.
/// Required for MenuBarExtra whose NSPanel has a forced dark appearance that
/// .preferredColorScheme() on the SwiftUI view cannot override.
struct WindowAppearanceSetter: NSViewRepresentable {
    let appearanceRaw: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Defer so the window is attached before we try to access it.
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.appearance = nsAppearance(for: appearanceRaw)
        }
    }

    private func nsAppearance(for raw: String) -> NSAppearance? {
        switch raw {
        case "light": return NSAppearance(named: .aqua)
        case "dark":  return NSAppearance(named: .darkAqua)
        default:      return nil  // nil = follow system
        }
    }
}

@main
struct RobinApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("appearance") private var appearanceRaw = "system"

    /// Converts the stored string preference to a SwiftUI ColorScheme (nil = follow system).
    private var preferredColorScheme: ColorScheme? {
        switch appearanceRaw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.engine)
                .environment(appDelegate.hotkey)
                .environment(appDelegate.overlay)
                .environment(appDelegate.permissions)
                .environment(appDelegate.downloads)
                .preferredColorScheme(preferredColorScheme)
                .background(WindowAppearanceSetter(appearanceRaw: appearanceRaw))
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
            .environment(appDelegate.hotkey)
            .environment(appDelegate.permissions)
            .environment(appDelegate.downloads)
            .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 560, height: 420)
        .windowResizability(.contentSize)

        Window("RCLI", id: "panel") {
            PanelView()
                .environment(appDelegate.engine)
                .environment(appDelegate.conversation)
                .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 420, height: 600)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(appDelegate.engine)
                .environment(appDelegate.hotkey)
                .environment(appDelegate.permissions)
                .environment(appDelegate.downloads)
                .environment(\.hotkeySetup, { appDelegate.setupHotkey() })
                .preferredColorScheme(preferredColorScheme)
        }
    }

    private var menuBarIcon: String {
        switch appDelegate.engine.lifecycleState {
        case .loading: return "circle.dashed"
        case .ready:
            switch appDelegate.engine.pipelineState {
            case .idle: return "waveform"
            case .listening: return "waveform"
            case .processing: return "bolt.fill"
            case .speaking: return "bolt.fill"
            case .interrupted: return "stop.circle"
            }
        case .error: return "exclamationmark.triangle"
        }
    }
}
