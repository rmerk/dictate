import Foundation
import CRCLIEngine

extension EngineService {
    func processCommand(_ text: String) async throws -> String {
        guard let h = handle else { throw RCLIError.engineNotReady }
        return try await withCheckedThrowingContinuation { cont in
            engineQueue.async {
                let result = rcli_process_command(h, text)
                guard let result else {
                    cont.resume(throwing: RCLIError.commandFailed("NULL response"))
                    return
                }
                let str = String(cString: result)
                cont.resume(returning: str)
            }
        }
    }

    func processAndSpeak(_ text: String) async throws -> String {
        guard let h = handle else { throw RCLIError.engineNotReady }
        return try await withCheckedThrowingContinuation { cont in
            engineQueue.async {
                let result = rcli_process_and_speak(h, text, nil, nil)
                guard let result else {
                    cont.resume(throwing: RCLIError.commandFailed("NULL response"))
                    return
                }
                let str = String(cString: result)
                cont.resume(returning: str)
            }
        }
    }

    func speak(_ text: String) async throws {
        guard let h = handle else { throw RCLIError.engineNotReady }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ttsQueue.async {
                let result = rcli_speak_streaming(h, text, nil, nil)
                if result != 0 {
                    cont.resume(throwing: RCLIError.speakFailed)
                    return
                }
                cont.resume()
            }
        }
    }

    func stopSpeaking() {
        guard let h = handle else { return }
        rcli_stop_speaking(h)
    }

    func clearHistory() {
        guard let h = handle else { return }
        engineQueue.async { rcli_clear_history(h) }
    }
}
