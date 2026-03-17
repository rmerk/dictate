import SwiftUI

struct ActionsSettingsView: View {
    @Environment(EngineService.self) private var engine
    @State private var actions: [ActionInfo] = []
    @State private var showCustomize = false
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading) {
            Form {
                Section {
                    HStack {
                        Text("Enabled actions")
                        Spacer()
                        Text("\(engine.enabledActionCount)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("Enable All") { engine.resetActionsToDefaults() }
                        Button("Disable All") { engine.disableAllActions() }
                    }
                }

                DisclosureGroup("Customize individual actions", isExpanded: $showCustomize) {
                    if actions.isEmpty {
                        ProgressView()
                    } else {
                        TextField("Search actions...", text: $searchText)

                        ForEach(filteredActions) { action in
                            Toggle(isOn: Binding(
                                get: { engine.isActionEnabled(action.name) },
                                set: { engine.setActionEnabled(action.name, enabled: $0) }
                            )) {
                                VStack(alignment: .leading) {
                                    Text(action.name).font(.body)
                                    if !action.description.isEmpty {
                                        Text(action.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding()
        .task {
            actions = await engine.listActions()
        }
    }

    private var filteredActions: [ActionInfo] {
        if searchText.isEmpty { return actions }
        return actions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }
}
