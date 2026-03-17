import Foundation
import CRCLIEngine

private struct ActionInfoJSON: Codable {
    let name: String
    let description: String?
    let category: String?
    let enabled: Bool?
}

extension EngineService {
    func listActions() async -> [ActionInfo] {
        guard let sh = optionalHandle() else { return [] }
        return await withCheckedContinuation { cont in
            engineQueue.async {
                guard let json = rcli_action_list(sh.raw) else {
                    cont.resume(returning: [])
                    return
                }
                let str = String(cString: json)
                guard let data = str.data(using: .utf8) else {
                    cont.resume(returning: [])
                    return
                }
                do {
                    let decoded = try JSONDecoder().decode([ActionInfoJSON].self, from: data)
                    let actions = decoded.map { json in
                        ActionInfo(
                            id: json.name,
                            name: json.name,
                            description: json.description ?? "",
                            category: json.category ?? "other",
                            isEnabled: json.enabled ?? true
                        )
                    }
                    cont.resume(returning: actions)
                } catch {
                    cont.resume(returning: [])
                }
            }
        }
    }

    func setActionEnabled(_ name: String, enabled: Bool) {
        guard let h = handle else { return }
        rcli_set_action_enabled(h, name, enabled ? 1 : 0)
        enabledActionCount = Int(rcli_num_actions_enabled(h))
    }

    func isActionEnabled(_ name: String) -> Bool {
        guard let h = handle else { return false }
        return rcli_is_action_enabled(h, name) != 0
    }

    func saveActionPreferences() throws {
        guard let h = handle else { throw RCLIError.engineNotReady }
        let result = rcli_save_action_preferences(h)
        if result != 0 { throw RCLIError.commandFailed("Failed to save action preferences") }
    }

    func disableAllActions() {
        guard let h = handle else { return }
        rcli_disable_all_actions(h)
        enabledActionCount = 0
    }

    func resetActionsToDefaults() {
        guard let h = handle else { return }
        rcli_reset_actions_to_defaults(h)
        enabledActionCount = Int(rcli_num_actions_enabled(h))
    }
}
