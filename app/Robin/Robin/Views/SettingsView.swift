import SwiftUI

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
    }
}
