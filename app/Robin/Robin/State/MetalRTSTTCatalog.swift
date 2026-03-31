import Foundation

enum MetalRTSTTCatalog {
    static let all: [MetalRTSTTEntry] = [
        MetalRTSTTEntry(
            id: "metalrt-whisper-tiny",
            name: "Whisper Tiny (MLX 4-bit)",
            sizeBytes: 40_000_000,
            description: "Fastest transcription, lower accuracy (~10% WER)",
            hfRepo: "runanywhere/whisper_tiny_4bit",
            tokenizerHFRepo: nil,
            hfSubdirectory: nil,
            localDirectory: "whisper-tiny-mlx-4bit",
            isDefault: true
        ),
        MetalRTSTTEntry(
            id: "metalrt-whisper-small",
            name: "Whisper Small (MLX 4-bit)",
            sizeBytes: 375_000_000,
            description: "Good balance of speed and accuracy (~5% WER)",
            hfRepo: "runanywhere/whisper_small_4bit",
            tokenizerHFRepo: nil,
            hfSubdirectory: "whisper-small-mlx-4bit",
            localDirectory: "whisper-small-mlx-4bit",
            isDefault: false
        ),
        MetalRTSTTEntry(
            id: "metalrt-whisper-medium",
            name: "Whisper Medium (MLX 4-bit)",
            sizeBytes: 980_000_000,
            description: "Best accuracy, slower (~3% WER)",
            hfRepo: "runanywhere/whisper_medium_4bit",
            tokenizerHFRepo: nil,
            hfSubdirectory: "whisper-medium-mlx-4bit",
            localDirectory: "whisper-medium-mlx-4bit",
            isDefault: false
        ),
        MetalRTSTTEntry(
            id: "metalrt-whisper-large-v3",
            name: "Whisper Large-v3 (MLX 4-bit)",
            sizeBytes: 973_124_280,
            description: "Most accurate Whisper model, slowest download and inference",
            hfRepo: "mlx-community/whisper-large-v3-mlx-4bit",
            tokenizerHFRepo: "openai/whisper-large-v3",
            hfSubdirectory: nil,
            localDirectory: "whisper-large-v3-mlx-4bit",
            isDefault: false
        ),
    ]

    static func entry(id: String) -> MetalRTSTTEntry? {
        all.first { $0.id == id }
    }

    static func entry(runtimeName: String) -> MetalRTSTTEntry? {
        all.first { $0.name == runtimeName }
    }

    static func installDirectory(for entry: MetalRTSTTEntry, modelsDir: String = defaultModelsDir) -> String {
        let metalRTDirectory = (modelsDir as NSString).appendingPathComponent("metalrt")
        return (metalRTDirectory as NSString).appendingPathComponent(entry.localDirectory)
    }

    static func isInstalled(_ entry: MetalRTSTTEntry, modelsDir: String = defaultModelsDir) -> Bool {
        let baseDirectory = installDirectory(for: entry, modelsDir: modelsDir)
        return entry.files.allSatisfy { file in
            FileManager.default.fileExists(
                atPath: (baseDirectory as NSString).appendingPathComponent(file.relativePath)
            )
        }
    }

    static func installedIDs(modelsDir: String = defaultModelsDir) -> Set<String> {
        Set(all.compactMap { entry in
            isInstalled(entry, modelsDir: modelsDir) ? entry.id : nil
        })
    }

    private static let defaultModelsDir = NSString(
        string: "~/Library/RCLI/models"
    ).expandingTildeInPath
}
