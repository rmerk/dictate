import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @Environment(EngineService.self) private var engine
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var selectedPersonality = "default"
    @State private var outputMode = "both"

    var body: some View {
        Form {
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

            Section("Output") {
                Picker("Response mode", selection: $outputMode) {
                    Text("Text only").tag("text")
                    Text("Voice only").tag("voice")
                    Text("Both").tag("both")
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
