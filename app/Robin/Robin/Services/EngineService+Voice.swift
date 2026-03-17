import Foundation
import CRCLIEngine

extension EngineService {
    func startListening() {
        guard let sh = optionalHandle() else { return }
        engineQueue.async { rcli_start_listening(sh.raw) }
    }

    func stopListening() {
        guard let sh = optionalHandle() else { return }
        engineQueue.async { rcli_stop_listening(sh.raw) }
    }

    func startCapture() {
        guard let sh = optionalHandle() else { return }
        engineQueue.async { rcli_start_capture(sh.raw) }
    }

    func stopAndTranscribe() async throws -> String {
        let sh = try requireHandle()
        return try await withCheckedThrowingContinuation { cont in
            engineQueue.async {
                let result = rcli_stop_capture_and_transcribe(sh.raw)
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
        let sh = try requireHandle()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            engineQueue.async {
                let result = rcli_start_voice_mode(sh.raw, wakePhrase)
                if result != 0 {
                    cont.resume(throwing: RCLIError.initFailed("Voice mode start failed"))
                    return
                }
                cont.resume()
            }
        }
    }

    func stopVoiceMode() {
        guard let sh = optionalHandle() else { return }
        engineQueue.async { rcli_stop_voice_mode(sh.raw) }
    }
}
