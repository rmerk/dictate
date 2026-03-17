import Foundation
import CRCLIEngine

extension EngineService {
    func ragIngest(directory: String) async throws {
        let sh = try requireHandle()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            engineQueue.async {
                let result = rcli_rag_ingest(sh.raw, directory)
                if result != 0 {
                    cont.resume(throwing: RCLIError.ragIngestFailed(directory))
                    return
                }
                cont.resume()
            }
        }
    }

    func ragLoadIndex(path: String) async throws {
        let sh = try requireHandle()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            engineQueue.async {
                let result = rcli_rag_load_index(sh.raw, path)
                if result != 0 {
                    cont.resume(throwing: RCLIError.ragIngestFailed("Failed to load index at \(path)"))
                    return
                }
                cont.resume()
            }
        }
    }

    func ragQuery(_ query: String) async throws -> String {
        let sh = try requireHandle()
        return try await withCheckedThrowingContinuation { cont in
            engineQueue.async {
                guard let result = rcli_rag_query(sh.raw, query) else {
                    cont.resume(throwing: RCLIError.commandFailed("RAG query returned nil"))
                    return
                }
                cont.resume(returning: String(cString: result))
            }
        }
    }

    func ragClear() {
        guard let sh = optionalHandle() else { return }
        engineQueue.async { rcli_rag_clear(sh.raw) }
    }
}
