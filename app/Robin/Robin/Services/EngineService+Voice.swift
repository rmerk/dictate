import Foundation
import CRCLIEngine

extension EngineService {
    func startListening() {
        guard let h = handle else { return }
        engineQueue.async { rcli_start_listening(h) }
    }

    func stopListening() {
        guard let h = handle else { return }
        engineQueue.async { rcli_stop_listening(h) }
    }

    func startCapture() {
        guard let h = handle else { return }
        engineQueue.async { rcli_start_capture(h) }
    }

    func stopAndTranscribe() async throws -> String {
        guard let h = handle else { throw RCLIError.engineNotReady }
        return try await withCheckedThrowingContinuation { cont in
            engineQueue.async {
                let result = rcli_stop_capture_and_transcribe(h)
                guard let result else {
                    cont.resume(throwing: RCLIError.transcriptionFailed)
                    return
                }
                let str = String(cString: result)
                cont.resume(returning: str)
            }
        }
    }

    func stopProcessing() {
        guard let h = handle else { return }
        rcli_stop_processing(h)
    }

    func startVoiceMode(wakePhrase: String) async throws {
        guard let h = handle else { throw RCLIError.engineNotReady }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            engineQueue.async {
                let result = rcli_start_voice_mode(h, wakePhrase)
                if result != 0 {
                    cont.resume(throwing: RCLIError.initFailed("Voice mode start failed"))
                    return
                }
                cont.resume()
            }
        }
    }

    func stopVoiceMode() {
        guard let h = handle else { return }
        engineQueue.async { rcli_stop_voice_mode(h) }
    }
}
