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
        // MARK: Dictation hotkey — capture → STT → route (auto) or paste (manual)
        hotkey.onHotkeyPressed = { [engine, hotkey, overlay, conversation] in
            Task { @MainActor in
                if hotkey.isRecording {
                    // Stop dictation recording
                    hotkey.setRecording(false)
                    overlay.setState(.transcribing)

                    do {
                        let text = try await engine.stopAndTranscribe()
                        guard !text.isEmpty else {
                            overlay.dismiss()
                            return
                        }

                        // Read live value at fire time — @AppStorage key matches HotkeysSettingsView
                        let routingMode = HotkeyRoutingMode(
                            rawValue: UserDefaults.standard.string(forKey: "hotkeyRoutingMode") ?? "manual"
                        ) ?? .manual

                        if routingMode == .auto {
                            let mode = HotkeyRouter.route(text, enabledActionCount: engine.enabledActionCount)
                            if mode == .command {
                                await Self.runCommand(text, engine: engine, conversation: conversation, overlay: overlay)
                            } else {
                                rcli_paste_text(text)
                                overlay.dismiss()
                            }
                        } else {
                            // Manual mode: dictation hotkey always pastes
                            rcli_paste_text(text)
                            overlay.dismiss()
                        }
                    } catch {
                        overlay.dismiss()
                    }
                } else {
                    // Ignore if command recording is already in progress
                    guard !hotkey.isCapturing else { return }

                    var caretX: Double = 0
                    var caretY: Double = 0
                    let caretFound = rcli_get_caret_position(&caretX, &caretY) == 0

                    if caretFound {
                        overlay.show(state: .recording, caretX: caretX, caretY: caretY)
                    } else {
                        overlay.show(state: .recording)
                    }

                    engine.startCapture()
                    hotkey.setRecording(true)
                }
            }
        }

        // MARK: Command hotkey — capture → STT → always run LLM + actions
        hotkey.onCommandHotkeyPressed = { [engine, hotkey, overlay, conversation] in
            Task { @MainActor in
                if hotkey.isCommandRecording {
                    // Stop command recording
                    hotkey.setCommandRecording(false)
                    overlay.setState(.transcribing)

                    do {
                        let text = try await engine.stopAndTranscribe()
                        guard !text.isEmpty else {
                            overlay.dismiss()
                            return
                        }
                        await Self.runCommand(text, engine: engine, conversation: conversation, overlay: overlay)
                    } catch {
                        overlay.dismiss()
                    }
                } else {
                    // Ignore if dictation recording is already in progress
                    guard !hotkey.isCapturing else { return }

                    var caretX: Double = 0
                    var caretY: Double = 0
                    let caretFound = rcli_get_caret_position(&caretX, &caretY) == 0

                    if caretFound {
                        overlay.show(state: .commanding, caretX: caretX, caretY: caretY)
                    } else {
                        overlay.show(state: .commanding)
                    }

                    engine.startCapture()
                    hotkey.setCommandRecording(true)
                }
            }
        }

        _ = hotkey.start()
    }

    /// Shared helper: transcribed text → processCommand → TTS + conversation store.
    @MainActor
    private static func runCommand(
        _ text: String,
        engine: EngineService,
        conversation: ConversationStore,
        overlay: OverlayService
    ) async {
        conversation.addUserMessage(text, method: .voice)
        let start = Date()
        do {
            let response = try await engine.processAndSpeak(text)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            conversation.addAssistantMessage(response, responseTimeMs: ms)
        } catch {
            conversation.addAssistantMessage("Error: \(error.localizedDescription)")
        }
        overlay.dismiss()
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

enum SettingsWindowCoordinator {
    enum RegularPresentationReason: Hashable {
        case onboarding
        case settings
    }

    @MainActor private static var regularPresentationReasons: Set<RegularPresentationReason> = []

    /// Tracks a regular-window flow and promotes the menu bar app only when the
    /// first such window is about to be shown.
    @MainActor
    private static func beginRegularPresentation(
        for reason: RegularPresentationReason,
        setActivationPolicy: (NSApplication.ActivationPolicy) -> Void,
        activate: (Bool) -> Void
    ) {
        regularPresentationReasons.insert(reason)
        if regularPresentationReasons.count == 1 {
            setActivationPolicy(.regular)
        }
        activate(true)
    }

    /// Releases a regular-window flow and demotes the app back to menu bar mode
    /// only after the last regular window flow has finished.
    @MainActor
    private static func endRegularPresentation(
        for reason: RegularPresentationReason,
        setActivationPolicy: (NSApplication.ActivationPolicy) -> Void
    ) {
        guard regularPresentationReasons.remove(reason) != nil else { return }
        guard regularPresentationReasons.isEmpty else { return }
        setActivationPolicy(.accessory)
    }

    /// Promotes the menu bar app to a regular app before opening Settings so
    /// macOS can reliably bring the window in front of other apps.
    @MainActor
    static func presentSettings(
        setActivationPolicy: (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) },
        activate: (Bool) -> Void = { NSApp.activate(ignoringOtherApps: $0) },
        openSettings: () -> Void
    ) {
        beginRegularPresentation(
            for: .settings,
            setActivationPolicy: setActivationPolicy,
            activate: activate
        )
        openSettings()
    }

    /// Promotes the app while onboarding is visible.
    @MainActor
    static func beginOnboardingPresentation(
        setActivationPolicy: (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) },
        activate: (Bool) -> Void = { NSApp.activate(ignoringOtherApps: $0) }
    ) {
        beginRegularPresentation(
            for: .onboarding,
            setActivationPolicy: setActivationPolicy,
            activate: activate
        )
    }

    /// Restores the menu bar presentation after the Settings window closes.
    @MainActor
    static func restoreMenuBarMode(
        setActivationPolicy: (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) }
    ) {
        endRegularPresentation(for: .settings, setActivationPolicy: setActivationPolicy)
    }

    /// Releases the onboarding presentation state after the welcome flow ends.
    @MainActor
    static func endOnboardingPresentation(
        setActivationPolicy: (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) }
    ) {
        endRegularPresentation(for: .onboarding, setActivationPolicy: setActivationPolicy)
    }

    /// Returns true when the notification belongs to the shared Settings window.
    static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.title == "Settings"
    }

    /// Only refocuses Settings when Robin is still the active app, which avoids
    /// stealing focus back after the user intentionally clicked another app.
    static func shouldRefocusSettingsWindow(_ window: NSWindow, appIsActive: Bool) -> Bool {
        isSettingsWindow(window) && appIsActive
    }

    /// Re-activates Settings after native controls temporarily steal key status.
    @MainActor
    static func refocusSettingsWindow(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
