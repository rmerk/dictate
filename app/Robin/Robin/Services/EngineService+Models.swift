import Foundation
import CRCLIEngine

private struct ModelInfoJSON: Codable {
    let id: String
    let name: String
    let size_bytes: Int64
    let type: String
    let is_downloaded: Bool
}

extension EngineService {
    var activeModelId: String? {
        ModelCatalog.all.first { $0.name == activeModel }?.id
    }

    var activeSTTModelId: String? {
        ModelCatalog.all.first { $0.name == activeSTTModel }?.id
    }

    var activeTTSModelId: String? {
        ModelCatalog.all.first { $0.name == activeTTSModel }?.id
    }

    func switchModel(_ id: String) async throws {
        let sh = try requireHandle()
        let (name, engine) = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(String, String), Error>) in
            engineQueue.async {
                let result = rcli_switch_llm(sh.raw, id)
                if result != 0 {
                    cont.resume(throwing: RCLIError.modelLoadFailed(id))
                    return
                }
                let name = String(cString: rcli_get_llm_model(sh.raw))
                let engine = String(cString: rcli_get_active_engine(sh.raw))
                cont.resume(returning: (name, engine))
            }
        }
        activeModel = name
        activeEngine = engine
        try? ConfigService.shared.write(key: "model", value: id)
    }

    func switchSTTModel(_ id: String) throws {
        guard let entry = ModelCatalog.all.first(where: { $0.id == id && $0.type == .stt }) else {
            throw RCLIError.modelNotFound(id)
        }
        try ConfigService.shared.write(key: "stt_model", value: id)
        activeSTTModel = entry.name
    }

    func switchTTSModel(_ id: String) throws {
        guard let entry = ModelCatalog.all.first(where: { $0.id == id && $0.type == .tts }) else {
            throw RCLIError.modelNotFound(id)
        }
        try ConfigService.shared.write(key: "tts_model", value: id)
        activeTTSModel = entry.name
    }

    func listAvailableModels() async throws -> [ModelInfo] {
        let sh = try requireHandle()
        return try await withCheckedThrowingContinuation { cont in
            engineQueue.async {
                guard let json = rcli_list_available_models(sh.raw) else {
                    cont.resume(returning: [])
                    return
                }
                let str = String(cString: json)
                free(json)

                guard let data = str.data(using: .utf8) else {
                    cont.resume(returning: [])
                    return
                }

                do {
                    let decoded = try JSONDecoder().decode([ModelInfoJSON].self, from: data)
                    let models = decoded.compactMap { json -> ModelInfo? in
                        guard let type = ModelType(rawValue: json.type) else { return nil }
                        return ModelInfo(id: json.id, name: json.name, sizeBytes: json.size_bytes,
                                        type: type, isDownloaded: json.is_downloaded)
                    }
                    cont.resume(returning: models)
                } catch {
                    cont.resume(returning: [])
                }
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
        guard let sh = optionalHandle() else { return "{}" }
        return await withCheckedContinuation { cont in
            engineQueue.async {
                let result = rcli_get_info(sh.raw)
                let str = result.map { String(cString: $0) } ?? "{}"
                cont.resume(returning: str)
            }
        }
    }

    func getContextInfo() async -> (promptTokens: Int, contextSize: Int) {
        guard let sh = optionalHandle() else { return (0, 0) }
        return await withCheckedContinuation { cont in
            engineQueue.async {
                var tokens: Int32 = 0
                var ctx: Int32 = 0
                rcli_get_context_info(sh.raw, &tokens, &ctx)
                cont.resume(returning: (Int(tokens), Int(ctx)))
            }
        }
    }
}
