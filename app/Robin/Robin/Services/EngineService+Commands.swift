import Foundation
import CRCLIEngine

extension EngineService {
    func processCommand(_ text: String) async throws -> String {
        let sh = try requireHandle()
        return try await withCheckedThrowingContinuation { cont in
            engineQueue.async {
                let result = rcli_process_command(sh.raw, text)
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
        let sh = try requireHandle()
        return try await withCheckedThrowingContinuation { cont in
            engineQueue.async {
                let result = rcli_process_and_speak(sh.raw, text, nil, nil)
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
        let sh = try requireHandle()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ttsQueue.async {
                let result = rcli_speak_streaming(sh.raw, text, nil, nil)
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
        guard let sh = optionalHandle() else { return }
        engineQueue.async { rcli_clear_history(sh.raw) }
    }
}
