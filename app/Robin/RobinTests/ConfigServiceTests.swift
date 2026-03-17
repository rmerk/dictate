import Testing
import Foundation
@testable import Robin

struct ConfigServiceTests {
    private func makeTempService() -> (ConfigService, String) {
        let path = NSTemporaryDirectory() + "rcli-test-config-\(UUID().uuidString)"
        return (ConfigService(configPath: path), path)
    }

    @Test func writeAndReadKey() throws {
        let (svc, path) = makeTempService()
        defer { try? FileManager.default.removeItem(atPath: path) }

        try svc.write(key: "model", value: "lfm2-1.2b")
        #expect(svc.read(key: "model") == "lfm2-1.2b")
    }

    @Test func replaceExistingKey() throws {
        let (svc, path) = makeTempService()
        defer { try? FileManager.default.removeItem(atPath: path) }

        try svc.write(key: "model", value: "lfm2-1.2b")
        try svc.write(key: "stt_model", value: "whisper-base")
        try svc.write(key: "model", value: "qwen3-0.6b")

        #expect(svc.read(key: "model") == "qwen3-0.6b")
        #expect(svc.read(key: "stt_model") == "whisper-base")
    }

    @Test func createFileIfMissing() throws {
        let (svc, path) = makeTempService()
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect(!FileManager.default.fileExists(atPath: path))
        try svc.write(key: "model", value: "lfm2-1.2b")
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(svc.read(key: "model") == "lfm2-1.2b")
    }

    @Test func readNilForMissingKey() {
        let (svc, path) = makeTempService()
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect(svc.read(key: "nonexistent") == nil)
    }
}
