import Foundation
import CRCLIEngine

extension EngineService {
    func ragIngest(directory: String) async throws {
        guard let h = handle else { throw RCLIError.engineNotReady }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            engineQueue.async {
                let result = rcli_rag_ingest(h, directory)
                if result != 0 {
                    cont.resume(throwing: RCLIError.ragIngestFailed(directory))
                    return
                }
                cont.resume()
            }
        }
    }

    func ragLoadIndex(path: String) async throws {
        guard let h = handle else { throw RCLIError.engineNotReady }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            engineQueue.async {
                let result = rcli_rag_load_index(h, path)
                if result != 0 {
                    cont.resume(throwing: RCLIError.ragIngestFailed("Failed to load index at \(path)"))
                    return
                }
                cont.resume()
            }
        }
    }

    func ragQuery(_ query: String) async throws -> String {
        guard let h = handle else { throw RCLIError.engineNotReady }
        return try await withCheckedThrowingContinuation { cont in
            engineQueue.async {
                guard let result = rcli_rag_query(h, query) else {
                    cont.resume(throwing: RCLIError.commandFailed("RAG query returned nil"))
                    return
                }
                cont.resume(returning: String(cString: result))
            }
        }
    }

    func ragClear() {
        guard let h = handle else { return }
        engineQueue.async { rcli_rag_clear(h) }
    }
}
