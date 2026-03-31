import SwiftUI
import AppKit
import Sparkle

struct SettingsView: View {
    @Environment(\.updater) private var updater

    var body: some View {
        TabView {
            GeneralSettingsView(updater: updater)
                .tabItem { Label("General", systemImage: "gear") }
            ModelsSettingsView()
                .tabItem { Label("Models", systemImage: "cpu") }
            HotkeysSettingsView()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            ActionsSettingsView()
                .tabItem { Label("Actions", systemImage: "bolt.fill") }
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }
        .frame(width: 500, height: 400)
        // After any native menu/picker dismisses, the Settings window loses key
        // status on macOS. Re-activate the app so the window comes back to front.
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didResignKeyNotification)
        ) { notification in
            guard let window = notification.object as? NSWindow,
                  SettingsWindowCoordinator.isSettingsWindow(window) else { return }
            DispatchQueue.main.async {
                guard SettingsWindowCoordinator.shouldRefocusSettingsWindow(
                    window,
                    appIsActive: NSApp.isActive
                ) else { return }
                SettingsWindowCoordinator.refocusSettingsWindow(window)
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.willCloseNotification)
        ) { notification in
            guard let window = notification.object as? NSWindow,
                  SettingsWindowCoordinator.isSettingsWindow(window) else { return }
            DispatchQueue.main.async {
                SettingsWindowCoordinator.restoreMenuBarMode()
            }
        }
    }
}
