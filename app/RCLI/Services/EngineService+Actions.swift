import Foundation
import CRCLIEngine

extension EngineService {
    func listActions() async -> [ActionInfo] {
        guard let h = handle else { return [] }
        return await withCheckedContinuation { cont in
            engineQueue.async {
                guard let json = rcli_action_list(h) else {
                    cont.resume(returning: [])
                    return
                }
                let str = String(cString: json)
                guard let data = str.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else {
                    cont.resume(returning: [])
                    return
                }
                let actions = arr.compactMap { dict -> ActionInfo? in
                    guard let name = dict["name"] as? String else { return nil }
                    return ActionInfo(
                        id: name,
                        name: name,
                        description: dict["description"] as? String ?? "",
                        category: dict["category"] as? String ?? "other",
                        isEnabled: dict["enabled"] as? Bool ?? true
                    )
                }
                cont.resume(returning: actions)
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
