import Foundation
import Observation
import CRCLIEngine

@MainActor
@Observable
final class EngineService {
    var lifecycleState: AppLifecycleState = .loading
    var pipelineState: PipelineState = .idle

    private var handle: RCLIHandle?
    private let engineQueue = DispatchQueue(label: "ai.rcli.engine")

    func initialize() async {
        lifecycleState = .loading

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                engineQueue.async {
                    let h = rcli_create(nil)
                    guard let h else {
                        cont.resume(throwing: RCLIError.initFailed("rcli_create returned nil"))
                        return
                    }

                    let modelsDir = NSString(string: "~/Library/RCLI/models").expandingTildeInPath
                    let result = rcli_init(h, modelsDir, 99)
                    if result != 0 {
                        rcli_destroy(h)
                        cont.resume(throwing: RCLIError.initFailed("rcli_init returned \(result)"))
                        return
                    }

                    Task { @MainActor in
                        self.handle = h
                    }
                    cont.resume()
                }
            }
            lifecycleState = .ready
        } catch {
            lifecycleState = .error(error.localizedDescription)
        }
    }

    func shutdown() {
        guard let h = handle else { return }
        handle = nil
        engineQueue.async {
            rcli_deregister_all_callbacks(h)
            rcli_destroy(h)
        }
    }
}

enum RCLIError: LocalizedError {
    case initFailed(String)
    case engineNotReady

    var errorDescription: String? {
        switch self {
        case .initFailed(let msg): return "Engine init failed: \(msg)"
        case .engineNotReady: return "Engine not ready"
        }
    }
}
