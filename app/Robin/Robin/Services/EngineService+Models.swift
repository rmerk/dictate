import Foundation
import CRCLIEngine

private struct ModelInfoJSON: Codable {
    let id: String
    let name: String
    let size_bytes: Int64
    let type: String
    let is_downloaded: Bool
}

enum ModelSelectionResolver {
    static func selectedSTTModelID(runtimeSTTName: String, persistedOfflineSTTID: String?) -> String? {
        if let persistedOfflineSTTID, !persistedOfflineSTTID.isEmpty {
            return persistedOfflineSTTID
        }

        return ModelCatalog.models(ofType: .stt).first { $0.name == runtimeSTTName }?.id
    }

    static func selectedMetalRTSTTModelID(runtimeSTTName: String, persistedMetalRTSTTID: String?) -> String? {
        if let persistedMetalRTSTTID,
           !persistedMetalRTSTTID.isEmpty,
           MetalRTSTTCatalog.entry(id: persistedMetalRTSTTID) != nil {
            return persistedMetalRTSTTID
        }

        return MetalRTSTTCatalog.entry(runtimeName: runtimeSTTName)?.id
    }
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

    var activeRuntimeSTTName: String {
        activeSTTModel
    }

    var activeMetalRTSTTModelId: String? {
        MetalRTSTTCatalog.entry(runtimeName: activeSTTModel)?.id
    }

    var persistedOfflineSTTModelId: String? {
        let modelID = ConfigService.shared.read(key: "stt_model")
        guard let modelID, !modelID.isEmpty else { return nil }
        return modelID
    }

    var persistedMetalRTSTTModelId: String? {
        let modelID = ConfigService.shared.read(key: "metalrt_stt")
        guard let modelID, !modelID.isEmpty else { return nil }
        return modelID
    }

    var isUsingMetalRT: Bool {
        activeEngine.caseInsensitiveCompare("metalrt") == .orderedSame
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
        selectedOfflineSTTModelId = entry.id
    }

    func switchTTSModel(_ id: String) throws {
        guard let entry = ModelCatalog.all.first(where: { $0.id == id && $0.type == .tts }) else {
            throw RCLIError.modelNotFound(id)
        }
        try ConfigService.shared.write(key: "tts_model", value: id)
        activeTTSModel = entry.name
    }

    func switchMetalRTSTTModel(_ id: String) async throws {
        guard let entry = MetalRTSTTCatalog.entry(id: id) else {
            throw RCLIError.modelNotFound(id)
        }
        guard isUsingMetalRT else {
            throw RCLIError.commandFailed("MetalRT STT is only available when the MetalRT engine is active.")
        }

        try ensureMetalRTSTTCanRestart()

        if activeMetalRTSTTModelId == entry.id && metalRTSTTApplyErrorMessage == nil {
            selectedMetalRTSTTModelId = entry.id
            return
        }

        guard let modelsDir = initializedModelsDir,
              let gpuLayers = initializedGPULayers else {
            throw RCLIError.engineNotReady
        }
        guard MetalRTSTTCatalog.isInstalled(entry, modelsDir: modelsDir) else {
            throw RCLIError.commandFailed("Download \(entry.name) before applying it.")
        }

        metalRTSTTApplyErrorMessage = nil
        isApplyingMetalRTSTTSelection = true
        selectedMetalRTSTTModelId = entry.id
        try ConfigService.shared.write(key: "metalrt_stt", value: entry.id)

        do {
            try await restartEngineForConfigurationChange(modelsDir: modelsDir, gpuLayers: gpuLayers)
        } catch {
            isApplyingMetalRTSTTSelection = false
            metalRTSTTApplyErrorMessage = error.localizedDescription
            throw error
        }
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

    private func ensureMetalRTSTTCanRestart() throws {
        if isApplyingMetalRTSTTSelection {
            throw RCLIError.commandFailed("Robin is already applying a MetalRT STT model.")
        }

        switch pipelineState {
        case .idle, .interrupted:
            return
        case .listening, .processing, .speaking:
            throw RCLIError.commandFailed(
                "Wait for dictation or playback to finish before switching the MetalRT STT model."
            )
        }
    }

    private func restartEngineForConfigurationChange(modelsDir: String, gpuLayers: Int) async throws {
        shutdown()
        do {
            try await initialize(modelsDir: modelsDir, gpuLayers: gpuLayers)
        } catch {
            lifecycleState = .error(error.localizedDescription)
            throw error
        }
    }
}
