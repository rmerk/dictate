import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
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
                  window.title == "Settings" else { return }
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
