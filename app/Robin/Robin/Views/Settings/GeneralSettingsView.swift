import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @Environment(EngineService.self) private var engine
    @AppStorage("appearance") private var appearanceRaw = "system"
    @State private var launchAtLogin = false
    @State private var selectedPersonality = "default"
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Color scheme", selection: $appearanceRaw) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue // revert
                        }
                    }
            }

            Section("Personality") {
                Picker("Voice personality", selection: $selectedPersonality) {
                    Text("Default").tag("default")
                    Text("Professional").tag("professional")
                    Text("Quirky").tag("quirky")
                    Text("Cynical").tag("cynical")
                    Text("Nerdy").tag("nerdy")
                }
                .onChange(of: selectedPersonality) { _, newValue in
                    try? engine.setPersonality(newValue)
                }
            }

        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            selectedPersonality = engine.personality
        }
    }
}
