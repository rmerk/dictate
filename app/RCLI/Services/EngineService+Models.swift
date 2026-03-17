import Foundation
import CRCLIEngine

extension EngineService {
    func switchModel(_ id: String) async throws {
        guard let h = handle else { throw RCLIError.engineNotReady }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            engineQueue.async { [weak self] in
                let result = rcli_switch_llm(h, id)
                if result != 0 {
                    cont.resume(throwing: RCLIError.modelLoadFailed(id))
                    return
                }
                let name = String(cString: rcli_get_llm_model(h))
                let engine = String(cString: rcli_get_active_engine(h))
                Task { @MainActor in
                    self?.activeModel = name
                    self?.activeEngine = engine
                }
                cont.resume()
            }
        }
    }

    func listAvailableModels() async throws -> [ModelInfo] {
        guard let h = handle else { throw RCLIError.engineNotReady }
        return try await withCheckedThrowingContinuation { cont in
            engineQueue.async {
                guard let json = rcli_list_available_models(h) else {
                    cont.resume(returning: [])
                    return
                }
                let str = String(cString: json)
                free(json)

                guard let data = str.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else {
                    cont.resume(returning: [])
                    return
                }

                let models = arr.compactMap { dict -> ModelInfo? in
                    guard let id = dict["id"] as? String,
                          let name = dict["name"] as? String,
                          let size = dict["size_bytes"] as? Int64,
                          let typeStr = dict["type"] as? String,
                          let type = ModelInfo.ModelType(rawValue: typeStr),
                          let downloaded = dict["is_downloaded"] as? Bool
                    else { return nil }
                    return ModelInfo(id: id, name: name, sizeBytes: size,
                                    type: type, isDownloaded: downloaded)
                }
                cont.resume(returning: models)
            }
        }
    }

    func setPersonality(_ key: String) throws {
        guard let h = handle else { throw RCLIError.engineNotReady }
        let result = rcli_set_personality(h, key)
        if result != 0 { throw RCLIError.commandFailed("Invalid personality: \(key)") }
        personality = key
    }

    func setBargeInEnabled(_ enabled: Bool) {
        guard let h = handle else { return }
        rcli_set_barge_in_enabled(h, enabled ? 1 : 0)
    }

    func isBargeInEnabled() -> Bool {
        guard let h = handle else { return false }
        return rcli_is_barge_in_enabled(h) != 0
    }

    func getInfo() async -> String {
        guard let h = handle else { return "{}" }
        return await withCheckedContinuation { cont in
            engineQueue.async {
                let result = rcli_get_info(h)
                let str = result.map { String(cString: $0) } ?? "{}"
                cont.resume(returning: str)
            }
        }
    }

    func getContextInfo() async -> (promptTokens: Int, contextSize: Int) {
        guard let h = handle else { return (0, 0) }
        return await withCheckedContinuation { cont in
            engineQueue.async {
                var tokens: Int32 = 0
                var ctx: Int32 = 0
                rcli_get_context_info(h, &tokens, &ctx)
                cont.resume(returning: (Int(tokens), Int(ctx)))
            }
        }
    }
}
