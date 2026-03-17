# Models View Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the empty Models settings tab with a working model catalog that shows all 18 models, lets users download/activate/delete them, and badges recommended models.

**Architecture:** Hardcoded Swift model catalog (`ModelCatalog`) drives the UI. `ModelDownloadService` handles downloads + archive extraction. `EngineService` handles activation + config persistence. No C API dependency for the catalog.

**Tech Stack:** SwiftUI, Swift Testing, URLSession, Process (for tar extraction)

**Spec:** `docs/superpowers/specs/2026-03-17-models-view-design.md`

---

## File Map

| File | Responsibility |
|------|---------------|
| `State/Types.swift` | `ModelType` (top-level), `ModelSource`, `ModelCatalogEntry` |
| **New:** `State/ModelCatalog.swift` | Hardcoded catalog of 18 models with URLs |
| **New:** `Services/ConfigService.swift` | Read/write `~/Library/RCLI/config` (key=value) |
| `Services/ModelDownloadService.swift` | Downloads, archive extraction, file deletion |
| `Services/EngineService+Models.swift` | `activeModelId` computed props, STT/TTS activation |
| `Views/Settings/ModelsSettingsView.swift` | Rewritten Models tab UI |
| `RobinApp.swift` | `ModelDownloadService` on `AppDelegate` |
| `Views/OnboardingView.swift` | Consume `ModelDownloadService` from environment |
| `RobinTests/ModelCatalogTests.swift` | Catalog integrity + matching tests |
| `RobinTests/ConfigServiceTests.swift` | Config file round-trip tests |

---

### Task 1: Extract `ModelType` to top-level and add new types

**Files:**
- Modify: `app/Robin/Robin/State/Types.swift`

- [ ] **Step 1: Extract `ModelType` enum to top-level**

Move `ModelInfo.ModelType` out of the struct and add `displayName`:

```swift
// Replace lines 40-42 with top-level enum (place before ModelInfo):

enum ModelType: String, Sendable {
    case llm, tts, stt

    var displayName: String {
        switch self {
        case .llm: return "LLM"
        case .stt: return "Speech-to-Text"
        case .tts: return "Text-to-Speech"
        }
    }
}
```

Update `ModelInfo` to remove the nested enum — change `let type: ModelType` (line 37) to reference the new top-level `ModelType`. Delete the nested `enum ModelType` block (lines 40-42).

Also update `EngineService+Models.swift` line 50: change `ModelInfo.ModelType(rawValue: typeStr)` to `ModelType(rawValue: typeStr)`.

- [ ] **Step 2: Add `ModelSource` enum and `ModelCatalogEntry` struct**

Add after `ModelType`:

```swift
enum ModelSource: Equatable, Sendable {
    case bundled
    case remote(URL)
}

struct ModelCatalogEntry: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let sizeBytes: Int64
    let type: ModelType
    let description: String
    let source: ModelSource
    let localPath: String
    let archiveDirName: String?
    let isRecommended: Bool

    var isArchive: Bool { type == .stt || type == .tts }
}
```

- [ ] **Step 3: Build to verify no compile errors**

Run: Cmd+B in Xcode (or `xcodebuild -project app/Robin/Robin.xcodeproj -scheme Robin build`)

Expected: Clean build. `ModelInfo` still works, now referencing top-level `ModelType`.

- [ ] **Step 4: Commit**

```bash
git add app/Robin/Robin/State/Types.swift
git commit -m "refactor: extract ModelType to top-level, add ModelCatalogEntry and ModelSource"
```

---

### Task 2: Create hardcoded `ModelCatalog`

**Files:**
- Create: `app/Robin/Robin/State/ModelCatalog.swift`

- [ ] **Step 1: Create `ModelCatalog.swift` with all 18 entries**

```swift
import Foundation

enum ModelCatalog {
    static let all: [ModelCatalogEntry] = [
        // MARK: - LLM Models
        ModelCatalogEntry(
            id: "lfm2-1.2b", name: "Liquid LFM2 1.2B Tool",
            sizeBytes: 731_000_000, type: .llm,
            description: "Default, excellent tool calling",
            source: .remote(URL(string: "https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q4_K_M.gguf")!),
            localPath: "lfm2-1.2b-tool-q4_k_m.gguf",
            archiveDirName: nil, isRecommended: true),
        ModelCatalogEntry(
            id: "lfm2-350m", name: "Liquid LFM2 350M",
            sizeBytes: 219_000_000, type: .llm,
            description: "Ultra-fast, basic tool calling",
            source: .remote(URL(string: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf")!),
            localPath: "LFM2-350M-Q4_K_M.gguf",
            archiveDirName: nil, isRecommended: false),
        ModelCatalogEntry(
            id: "lfm2.5-1.2b", name: "Liquid LFM2.5 1.2B Instruct",
            sizeBytes: 731_000_000, type: .llm,
            description: "Newer LFM, good tool calling",
            source: .remote(URL(string: "https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf")!),
            localPath: "LFM2.5-1.2B-Instruct-Q4_K_M.gguf",
            archiveDirName: nil, isRecommended: false),
        ModelCatalogEntry(
            id: "lfm2-2.6b", name: "Liquid LFM2 2.6B",
            sizeBytes: 1_480_000_000, type: .llm,
            description: "Larger LFM, good tool calling",
            source: .remote(URL(string: "https://huggingface.co/LiquidAI/LFM2-2.6B-GGUF/resolve/main/LFM2-2.6B-Q4_K_M.gguf")!),
            localPath: "LFM2-2.6B-Q4_K_M.gguf",
            archiveDirName: nil, isRecommended: false),
        ModelCatalogEntry(
            id: "qwen3-0.6b", name: "Qwen3 0.6B",
            sizeBytes: 456_000_000, type: .llm,
            description: "Fast, basic tool calling",
            source: .remote(URL(string: "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/qwen3-0.6b-q4_k_m.gguf")!),
            localPath: "qwen3-0.6b-q4_k_m.gguf",
            archiveDirName: nil, isRecommended: false),
        ModelCatalogEntry(
            id: "qwen3.5-0.8b", name: "Qwen3.5 0.8B",
            sizeBytes: 600_000_000, type: .llm,
            description: "Compact Qwen, basic tool calling",
            source: .remote(URL(string: "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf")!),
            localPath: "qwen3.5-0.8b-q4_k_m.gguf",
            archiveDirName: nil, isRecommended: false),
        ModelCatalogEntry(
            id: "qwen3.5-2b", name: "Qwen3.5 2B",
            sizeBytes: 1_200_000_000, type: .llm,
            description: "Balanced Qwen, good tool calling",
            source: .remote(URL(string: "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf")!),
            localPath: "qwen3.5-2b-q4_k_m.gguf",
            archiveDirName: nil, isRecommended: false),
        ModelCatalogEntry(
            id: "qwen3-4b", name: "Qwen3 4B",
            sizeBytes: 2_500_000_000, type: .llm,
            description: "Large Qwen, good tool calling",
            source: .remote(URL(string: "https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf")!),
            localPath: "qwen3-4b-q4_k_m.gguf",
            archiveDirName: nil, isRecommended: false),
        ModelCatalogEntry(
            id: "qwen3.5-4b", name: "Qwen3.5 4B",
            sizeBytes: 2_700_000_000, type: .llm,
            description: "Smartest, excellent tool calling",
            source: .remote(URL(string: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf")!),
            localPath: "qwen3.5-4b-q4_k_m.gguf",
            archiveDirName: nil, isRecommended: true),
        ModelCatalogEntry(
            id: "llama3.2-3b", name: "Llama 3.2 3B Instruct",
            sizeBytes: 1_800_000_000, type: .llm,
            description: "Meta Llama, good tool calling",
            source: .remote(URL(string: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf")!),
            localPath: "llama-3.2-3b-instruct-q4_k_m.gguf",
            archiveDirName: nil, isRecommended: false),

        // MARK: - STT Models
        ModelCatalogEntry(
            id: "whisper-base", name: "Whisper base.en",
            sizeBytes: 140_000_000, type: .stt,
            description: "Offline transcription, ~5% WER",
            source: .bundled,
            localPath: "whisper-base.en",
            archiveDirName: "sherpa-onnx-whisper-base.en", isRecommended: true),
        ModelCatalogEntry(
            id: "parakeet-tdt", name: "Parakeet TDT 0.6B v3",
            sizeBytes: 640_000_000, type: .stt,
            description: "Best accuracy, ~1.9% WER",
            source: .remote(URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2")!),
            localPath: "parakeet-tdt",
            archiveDirName: "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8",
            isRecommended: true),

        // MARK: - TTS Models
        ModelCatalogEntry(
            id: "piper-lessac", name: "Piper Lessac (English)",
            sizeBytes: 60_000_000, type: .tts,
            description: "Default English voice",
            source: .bundled,
            localPath: "piper-voice",
            archiveDirName: "vits-piper-en_US-lessac-medium", isRecommended: true),
        ModelCatalogEntry(
            id: "piper-amy", name: "Piper Amy (English)",
            sizeBytes: 60_000_000, type: .tts,
            description: "Alternative English voice",
            source: .remote(URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-amy-medium.tar.bz2")!),
            localPath: "piper-amy",
            archiveDirName: "vits-piper-en_US-amy-medium",
            isRecommended: false),
        ModelCatalogEntry(
            id: "kitten-nano", name: "KittenTTS Nano (English)",
            sizeBytes: 90_000_000, type: .tts,
            description: "8 voices, great quality",
            source: .remote(URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kitten-nano-en-v0_1-fp16.tar.bz2")!),
            localPath: "kitten-nano-en-v0_1-fp16",
            archiveDirName: nil, isRecommended: false),
        ModelCatalogEntry(
            id: "matcha-ljspeech", name: "Matcha LJSpeech (English)",
            sizeBytes: 100_000_000, type: .tts,
            description: "Great quality",
            source: .remote(URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/matcha-icefall-en_US-ljspeech.tar.bz2")!),
            localPath: "matcha-icefall-en_US-ljspeech",
            archiveDirName: nil, isRecommended: false),
        ModelCatalogEntry(
            id: "kokoro-en", name: "Kokoro English v0.19",
            sizeBytes: 310_000_000, type: .tts,
            description: "11 voices, excellent quality",
            source: .remote(URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-en-v0_19.tar.bz2")!),
            localPath: "kokoro-en-v0_19",
            archiveDirName: nil, isRecommended: true),
        ModelCatalogEntry(
            id: "kokoro-multi", name: "Kokoro Multi-lang v1.1",
            sizeBytes: 500_000_000, type: .tts,
            description: "103 voices, Chinese + English",
            source: .remote(URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_1.tar.bz2")!),
            localPath: "kokoro-multi-lang-v1_1",
            archiveDirName: nil, isRecommended: false),
    ]

    static func models(ofType type: ModelType) -> [ModelCatalogEntry] {
        all.filter { $0.type == type }
            .sorted { ($0.isRecommended ? 0 : 1) < ($1.isRecommended ? 0 : 1) }
    }

    #if DEBUG
    static let _validateUniqueness: Void = {
        assert(Set(all.map(\.id)).count == all.count, "Duplicate model IDs in catalog")
        assert(Set(all.map(\.localPath)).count == all.count, "Duplicate localPaths in catalog")
    }()
    #endif
}
```

- [ ] **Step 2: Add file to Xcode project and build**

Add `ModelCatalog.swift` to the Robin target in Xcode. Build to verify.

- [ ] **Step 3: Commit**

```bash
git add app/Robin/Robin/State/ModelCatalog.swift
git commit -m "feat: add hardcoded ModelCatalog with 18 model entries"
```

---

### Task 3: Write `ModelCatalog` tests

**Files:**
- Create: `app/Robin/RobinTests/ModelCatalogTests.swift`

- [ ] **Step 1: Write catalog integrity tests**

```swift
import Testing
@testable import Robin

struct ModelCatalogTests {
    @Test func catalogHasUniqueIDs() {
        let ids = ModelCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count, "Duplicate IDs found")
    }

    @Test func catalogHasUniqueLocalPaths() {
        let paths = ModelCatalog.all.map(\.localPath)
        #expect(Set(paths).count == paths.count, "Duplicate localPaths found")
    }

    @Test func allRemoteModelsHaveURLs() {
        for entry in ModelCatalog.all {
            if case .bundled = entry.source {
                // bundled models: whisper-base, piper-lessac
                #expect(entry.id == "whisper-base" || entry.id == "piper-lessac")
            }
        }
    }

    @Test func archiveFlagDerivedFromType() {
        for entry in ModelCatalog.all {
            if entry.type == .llm {
                #expect(!entry.isArchive, "\(entry.id) is LLM but isArchive is true")
            } else {
                #expect(entry.isArchive, "\(entry.id) is STT/TTS but isArchive is false")
            }
        }
    }

    @Test func recommendedModelsSortFirst() {
        for type in [ModelType.llm, .stt, .tts] {
            let models = ModelCatalog.models(ofType: type)
            guard let firstNonRec = models.firstIndex(where: { !$0.isRecommended }) else { continue }
            let anyRecAfter = models[firstNonRec...].contains { $0.isRecommended }
            #expect(!anyRecAfter, "Recommended model sorted after non-recommended for \(type)")
        }
    }

    @Test func catalogHasExpectedCount() {
        #expect(ModelCatalog.all.count == 18)
        #expect(ModelCatalog.models(ofType: .llm).count == 10)
        #expect(ModelCatalog.models(ofType: .stt).count == 2)
        #expect(ModelCatalog.models(ofType: .tts).count == 6)
    }

    @Test func activeModelIdExactMatch() {
        // Exact match should find the model
        let match = ModelCatalog.all.first { $0.name == "Liquid LFM2 1.2B Tool" }
        #expect(match?.id == "lfm2-1.2b")
    }

    @Test func activeModelIdNoFalsePositive() {
        // "Liquid LFM2.5 1.2B Instruct" should NOT match "Liquid LFM2 1.2B Tool"
        let match = ModelCatalog.all.first { $0.name == "Liquid LFM2.5 1.2B Instruct" }
        #expect(match?.id == "lfm2.5-1.2b")
        #expect(match?.id != "lfm2-1.2b")
    }

    @Test func activeModelIdNilForUnknown() {
        let match = ModelCatalog.all.first { $0.name == "Unknown Model XYZ" }
        #expect(match == nil)
    }
}
```

- [ ] **Step 2: Add file to Xcode project, run tests**

Add `ModelCatalogTests.swift` to RobinTests target. Run: Cmd+U in Xcode.

Expected: All 8 tests pass.

- [ ] **Step 3: Commit**

```bash
git add app/Robin/RobinTests/ModelCatalogTests.swift
git commit -m "test: add ModelCatalog integrity and matching tests"
```

---

### Task 4: Create `ConfigService`

**Files:**
- Create: `app/Robin/Robin/Services/ConfigService.swift`

- [ ] **Step 1: Write `ConfigService`**

```swift
import Foundation

struct ConfigService {
    static let shared = ConfigService()

    let configPath: String

    init(configPath: String = NSString(
            string: "~/Library/RCLI/config").expandingTildeInPath) {
        self.configPath = configPath
    }

    func read(key: String) -> String? {
        guard let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return nil
        }
        for line in contents.components(separatedBy: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 && parts[0] == key {
                return String(parts[1])
            }
        }
        return nil
    }

    func write(key: String, value: String) throws {
        let fm = FileManager.default
        var lines: [String] = []

        if fm.fileExists(atPath: configPath) {
            let contents = try String(contentsOfFile: configPath, encoding: .utf8)
            lines = contents.components(separatedBy: "\n")
        } else {
            let dir = (configPath as NSString).deletingLastPathComponent
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let prefix = "\(key)="
        var replaced = false
        for i in lines.indices {
            if lines[i].hasPrefix(prefix) {
                lines[i] = "\(key)=\(value)"
                replaced = true
                break
            }
        }
        if !replaced {
            while lines.last?.isEmpty == true { lines.removeLast() }
            lines.append("\(key)=\(value)")
        }

        let output = lines.joined(separator: "\n") + "\n"
        try output.write(toFile: configPath, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 2: Build to verify**

Run: Cmd+B in Xcode. Expected: Clean build.

- [ ] **Step 3: Commit**

```bash
git add app/Robin/Robin/Services/ConfigService.swift
git commit -m "feat: add ConfigService for reading/writing ~/Library/RCLI/config"
```

---

### Task 5: Write `ConfigService` tests

**Files:**
- Create: `app/Robin/RobinTests/ConfigServiceTests.swift`

- [ ] **Step 1: Write config round-trip tests**

```swift
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
```

- [ ] **Step 2: Run tests**

Run: Cmd+U in Xcode. Expected: All 3 tests pass.

- [ ] **Step 3: Commit**

```bash
git add app/Robin/RobinTests/ConfigServiceTests.swift
git commit -m "test: add ConfigService round-trip tests"
```

---

### Task 6: Update `ModelDownloadService` — destination filename, extraction, deletion

**Files:**
- Modify: `app/Robin/Robin/Services/ModelDownloadService.swift`

- [ ] **Step 1: Add `destinationFilenames` dictionary and update `download()` signature**

Add a new stored property and update the download method:

```swift
// Add after line 21 (private var continuations):
private var destinationFilenames: [String: String] = [:]
```

Update the `download` method signature (line 35) to accept a destination filename:

```swift
func download(modelId: String, name: String, url: URL, destinationFilename: String) async throws {
    let task = session.downloadTask(with: url)
    task.taskDescription = modelId
    activeDownloads[modelId] = DownloadProgress(
        modelId: modelId, modelName: name, totalBytes: 0)
    destinationFilenames[modelId] = destinationFilename

    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        continuations[modelId] = cont
        task.resume()
    }
}
```

- [ ] **Step 2: Fix `didFinishDownloadingTo` to use `destinationFilename`**

Replace lines 63-86 (the `didFinishDownloadingTo` method):

```swift
nonisolated func urlSession(_ session: URLSession,
                            downloadTask: URLSessionDownloadTask,
                            didFinishDownloadingTo location: URL) {
    let modelId = downloadTask.taskDescription ?? ""

    // Use the catalog-specified filename, not suggestedFilename
    let filename: String
    if Thread.isMainThread {
        filename = MainActor.assumeIsolated { destinationFilenames[modelId] ?? modelId }
    } else {
        filename = DispatchQueue.main.sync { destinationFilenames[modelId] ?? modelId }
    }
    let dest = URL(fileURLWithPath: modelsDir)
        .appendingPathComponent(filename)

    do {
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: location, to: dest)

        Task { @MainActor in
            self.destinationFilenames.removeValue(forKey: modelId)
            self.activeDownloads.removeValue(forKey: modelId)
            self.completedDownloads.insert(modelId)
            self.continuations.removeValue(forKey: modelId)?.resume()
        }
    } catch {
        Task { @MainActor in
            self.activeDownloads[modelId]?.failed = true
            self.activeDownloads[modelId]?.errorMessage = error.localizedDescription
            self.continuations.removeValue(forKey: modelId)?.resume(throwing: error)
        }
    }
}
```

- [ ] **Step 3: Fix cancel race condition**

Replace the `cancelDownload` method (lines 47-55). Only cancel the URLSession task — let the delegate handle continuation resume:

```swift
func cancelDownload(modelId: String) {
    activeDownloads.removeValue(forKey: modelId)
    destinationFilenames.removeValue(forKey: modelId)
    session.getAllTasks { [weak self] tasks in
        tasks.first { $0.taskDescription == modelId }?.cancel()
    }
    // Do NOT resume continuation here — let didCompleteWithError handle it
    // with NSURLErrorCancelled. This prevents double-resume crashes.
}
```

- [ ] **Step 4: Add `extractArchive` method**

Add after the `cancelDownload` method:

```swift
func extractArchive(archivePath: String, to directory: String,
                    archiveDirName: String?, renameTo localPath: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    process.arguments = ["xjf", archivePath, "-C", directory]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        // Clean up partial extraction
        let extractedDir = archiveDirName ?? localPath
        let partialPath = (directory as NSString).appendingPathComponent(extractedDir)
        try? FileManager.default.removeItem(atPath: partialPath)
        throw RCLIError.commandFailed("Archive extraction failed (exit \(process.terminationStatus))")
    }

    // Rename archive dir to expected localPath if needed
    if let archiveDir = archiveDirName, archiveDir != localPath {
        let srcPath = (directory as NSString).appendingPathComponent(archiveDir)
        let dstPath = (directory as NSString).appendingPathComponent(localPath)
        if FileManager.default.fileExists(atPath: dstPath) {
            try FileManager.default.removeItem(atPath: dstPath)
        }
        try FileManager.default.moveItem(atPath: srcPath, toPath: dstPath)
    }

    // Verify extraction succeeded
    let finalPath = (directory as NSString).appendingPathComponent(localPath)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: finalPath, isDirectory: &isDir),
          isDir.boolValue else {
        throw RCLIError.commandFailed("Extracted directory not found: \(localPath)")
    }

    // Only delete archive after verified extraction
    try? FileManager.default.removeItem(atPath: archivePath)
}
```

- [ ] **Step 5: Add `deleteModel` method**

```swift
func deleteModel(path: String, isDirectory: Bool) throws {
    let fullPath = (modelsDir as NSString).appendingPathComponent(path)
    guard FileManager.default.fileExists(atPath: fullPath) else { return }
    try FileManager.default.removeItem(atPath: fullPath)
}
```

- [ ] **Step 6: Build to verify**

Run: Cmd+B. Expected: Clean build.

- [ ] **Step 7: Commit**

```bash
git add app/Robin/Robin/Services/ModelDownloadService.swift
git commit -m "feat: ModelDownloadService — destination filename, archive extraction, delete, cancel fix"
```

---

### Task 7: Update `EngineService+Models.swift` — active model IDs, STT/TTS activation, config persistence

**Files:**
- Modify: `app/Robin/Robin/Services/EngineService+Models.swift`

- [ ] **Step 1: Add `activeModelId` computed properties**

Add at the top of the extension (after line 4):

```swift
    var activeModelId: String? {
        ModelCatalog.all.first { $0.name == activeModel }?.id
    }

    var activeSTTModelId: String? {
        ModelCatalog.all.first { $0.name == activeSTTModel }?.id
    }

    var activeTTSModelId: String? {
        ModelCatalog.all.first { $0.name == activeTTSModel }?.id
    }
```

- [ ] **Step 2: Add config persistence to `switchModel`**

In `EngineService+Models.swift`, replace lines 17-20 (the `Task { @MainActor in` block inside `switchModel`) with:

```swift
// The outer closure captures `id` from switchModel's parameter.
// `name` and `engine` are already defined above from C API calls.
Task { @MainActor [weak self] in
    self?.activeModel = name
    self?.activeEngine = engine
    try? ConfigService.shared.write(key: "model", value: id)
}
```

This persists the LLM selection to `~/Library/RCLI/config` so it survives app restarts.

- [ ] **Step 3: Add `switchSTTModel` and `switchTTSModel`**

Add after the `switchModel` method:

```swift
    func switchSTTModel(_ id: String) throws {
        guard let entry = ModelCatalog.all.first(where: { $0.id == id && $0.type == .stt }) else {
            throw RCLIError.modelNotFound(id)
        }
        try ConfigService.shared.write(key: "stt_model", value: id)
        activeSTTModel = entry.name
    }

    func switchTTSModel(_ id: String) throws {
        guard let entry = ModelCatalog.all.first(where: { $0.id == id && $0.type == .tts }) else {
            throw RCLIError.modelNotFound(id)
        }
        try ConfigService.shared.write(key: "tts_model", value: id)
        activeTTSModel = entry.name
    }
```

- [ ] **Step 4: Build to verify**

Run: Cmd+B. Expected: Clean build.

- [ ] **Step 5: Commit**

```bash
git add app/Robin/Robin/Services/EngineService+Models.swift
git commit -m "feat: active model ID matching, STT/TTS activation, config persistence"
```

---

### Task 8: Move `ModelDownloadService` to `AppDelegate`

**Files:**
- Modify: `app/Robin/Robin/RobinApp.swift`
- Modify: `app/Robin/Robin/Views/OnboardingView.swift`

- [ ] **Step 1: Add `ModelDownloadService` to `AppDelegate`**

In `RobinApp.swift`, add to `AppDelegate` (after line 8):

```swift
let downloads = ModelDownloadService()
```

- [ ] **Step 2: Inject via `.environment()` on all scenes**

Add `.environment(appDelegate.downloads)` to all scenes that need it. In the `body` property:

- After `.environment(appDelegate.permissions)` on the MenuBarExtra (line 79), add:
  `.environment(appDelegate.downloads)`
- After `.environment(appDelegate.permissions)` on the onboarding Window (line 93), add:
  `.environment(appDelegate.downloads)`
- After `.environment(appDelegate.permissions)` on the Settings (line 109), add:
  `.environment(appDelegate.downloads)`

- [ ] **Step 3: Update `OnboardingView` to use environment**

In `OnboardingView.swift`:

Replace line 11 (`@State private var downloadService = ModelDownloadService()`):
```swift
@Environment(ModelDownloadService.self) private var downloadService
```

- [ ] **Step 4: Build to verify**

Run: Cmd+B. Expected: Clean build.

- [ ] **Step 5: Commit**

```bash
git add app/Robin/Robin/RobinApp.swift app/Robin/Robin/Views/OnboardingView.swift
git commit -m "refactor: move ModelDownloadService to AppDelegate, inject via environment"
```

---

### Task 9: Rewrite `ModelsSettingsView`

**Files:**
- Modify: `app/Robin/Robin/Views/Settings/ModelsSettingsView.swift`

- [ ] **Step 1: Rewrite the view**

Replace the entire file:

```swift
import SwiftUI

struct ModelsSettingsView: View {
    @Environment(EngineService.self) private var engine
    @Environment(ModelDownloadService.self) private var downloads
    @State private var downloadedPaths: Set<String> = []
    @State private var modelToDelete: ModelCatalogEntry?

    private let modelsDir = NSString(
        string: "~/Library/RCLI/models").expandingTildeInPath

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if downloadedPaths.isEmpty && downloads.activeDownloads.isEmpty {
                ContentUnavailableView {
                    Label("No Models", systemImage: "square.and.arrow.down")
                } description: {
                    Text("No models downloaded yet.\nDownload recommended models to get started.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    modelSection(type: .llm)
                    modelSection(type: .stt)
                    modelSection(type: .tts)
                }
            }

            diskUsageFooter
        }
        .task { refreshDownloadedState() }
        .alert("Delete Model",
               isPresented: Binding(
                   get: { modelToDelete != nil },
                   set: { if !$0 { modelToDelete = nil } }
               )) {
            Button("Cancel", role: .cancel) { modelToDelete = nil }
            Button("Delete", role: .destructive) { deleteModel() }
        } message: {
            if let m = modelToDelete {
                Text("Delete \(m.name)? This will free \(formatSize(m.sizeBytes)).")
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func modelSection(type: ModelType) -> some View {
        Section(type.displayName) {
            ForEach(ModelCatalog.models(ofType: type)) { entry in
                modelRow(entry)
            }
        }
    }

    // MARK: - Model Row

    @ViewBuilder
    private func modelRow(_ entry: ModelCatalogEntry) -> some View {
        let isActive = isModelActive(entry)
        let isDownloaded = downloadedPaths.contains(entry.localPath)
        let progress = downloads.activeDownloads[entry.id]

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name).font(.body.bold())
                    if entry.isRecommended {
                        Text("Recommended")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }
                Text("\(formatSize(entry.sizeBytes)) · \(entry.description)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Right side: state-dependent controls
            if let progress {
                if progress.failed {
                    failedView(entry, message: progress.errorMessage)
                } else {
                    downloadingView(entry, progress: progress)
                }
            } else if isActive {
                activeView(entry)
            } else if isDownloaded {
                downloadedView(entry)
            } else if case .remote = entry.source {
                downloadButton(entry)
            }
            // .bundled + not downloaded: show nothing (installed by rcli setup)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Row States

    private func downloadButton(_ entry: ModelCatalogEntry) -> some View {
        Button("Download") {
            Task { await startDownload(entry) }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    private func downloadingView(_ entry: ModelCatalogEntry, progress: ModelDownloadService.DownloadProgress) -> some View {
        HStack(spacing: 8) {
            ProgressView(value: progress.fraction)
                .frame(width: 80)
            Text("\(Int(progress.fraction * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 30)
            Button {
                downloads.cancelDownload(modelId: entry.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func failedView(_ entry: ModelCatalogEntry, message: String?) -> some View {
        HStack(spacing: 6) {
            Text(message ?? "Download failed")
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(1)
            Button("Retry") {
                Task { await startDownload(entry) }
            }
            .controlSize(.small)
        }
    }

    private func activeView(_ entry: ModelCatalogEntry) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 2) {
                Text("Active")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(4)
                if entry.type == .stt || entry.type == .tts {
                    Text("Takes effect on next launch")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Button {
                // disabled — can't delete active model
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(true)
        }
    }

    private func downloadedView(_ entry: ModelCatalogEntry) -> some View {
        HStack(spacing: 8) {
            Button("Activate") {
                Task { await activateModel(entry) }
            }
            .controlSize(.small)

            Button {
                modelToDelete = entry
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Disk Usage Footer

    private var diskUsageFooter: some View {
        HStack {
            Text("Disk Usage:")
                .font(.caption)
                .foregroundColor(.secondary)
            let totalBytes = ModelCatalog.all
                .filter { downloadedPaths.contains($0.localPath) }
                .reduce(Int64(0)) { $0 + $1.sizeBytes }
            Text(formatSize(totalBytes))
                .font(.caption)
            Spacer()
        }
        .padding()
    }

    // MARK: - Actions

    private func startDownload(_ entry: ModelCatalogEntry) async {
        guard case .remote(let url) = entry.source else { return }

        // Disk space check
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: modelsDir),
           let freeSpace = attrs[.systemFreeSize] as? Int64 {
            let needed = entry.isArchive ? entry.sizeBytes * 2 : Int64(Double(entry.sizeBytes) * 1.1)
            if freeSpace < needed {
                downloads.activeDownloads[entry.id] = .init(
                    modelId: entry.id, modelName: entry.name,
                    failed: true,
                    errorMessage: "Not enough disk space. \(formatSize(needed)) required, \(formatSize(freeSpace)) available.")
                return
            }
        }

        // For archives, download to a temp .tar.bz2 file
        let destFilename = entry.isArchive ? "\(entry.id).tar.bz2" : entry.localPath

        do {
            try await downloads.download(
                modelId: entry.id, name: entry.name,
                url: url, destinationFilename: destFilename)

            if entry.isArchive {
                let archivePath = (modelsDir as NSString)
                    .appendingPathComponent(destFilename)
                try downloads.extractArchive(
                    archivePath: archivePath, to: modelsDir,
                    archiveDirName: entry.archiveDirName,
                    renameTo: entry.localPath)
            }

            refreshDownloadedState()
        } catch is CancellationError {
            // User cancelled — already handled
        } catch {
            downloads.activeDownloads[entry.id] = .init(
                modelId: entry.id, modelName: entry.name,
                failed: true, errorMessage: error.localizedDescription)
        }
    }

    private func activateModel(_ entry: ModelCatalogEntry) async {
        do {
            switch entry.type {
            case .llm:
                try await engine.switchModel(entry.id)
            case .stt:
                try engine.switchSTTModel(entry.id)
            case .tts:
                try engine.switchTTSModel(entry.id)
            }
        } catch {
            // Show error — for now just log
            print("Activation failed: \(error)")
        }
    }

    private func deleteModel() {
        guard let entry = modelToDelete else { return }
        modelToDelete = nil

        // Service-layer guard: don't delete active model
        guard !isModelActive(entry) else { return }

        do {
            try downloads.deleteModel(
                path: entry.localPath, isDirectory: entry.isArchive)
            refreshDownloadedState()
        } catch {
            print("Delete failed: \(error)")
        }
    }

    // MARK: - Helpers

    private func isModelActive(_ entry: ModelCatalogEntry) -> Bool {
        switch entry.type {
        case .llm: return entry.id == engine.activeModelId
        case .stt: return entry.id == engine.activeSTTModelId
        case .tts: return entry.id == engine.activeTTSModelId
        }
    }

    private func refreshDownloadedState() {
        let fm = FileManager.default
        var paths = Set<String>()
        for entry in ModelCatalog.all {
            let full = (modelsDir as NSString).appendingPathComponent(entry.localPath)
            if fm.fileExists(atPath: full) {
                paths.insert(entry.localPath)
            }
        }
        downloadedPaths = paths
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 {
            return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
        } else {
            return "\(bytes / 1_000_000) MB"
        }
    }
}
```

- [ ] **Step 2: Build and run**

Run: Cmd+B then Cmd+R. Open Settings > Models tab.

Expected: All 18 models appear in 3 sections, recommended models sort first with green badges, disk usage footer shows. Downloaded models show Active/Activate/Download as appropriate.

- [ ] **Step 3: Commit**

```bash
git add app/Robin/Robin/Views/Settings/ModelsSettingsView.swift
git commit -m "feat: rewrite ModelsSettingsView with catalog, download, activate, delete"
```

---

### Task 10: Final integration and manual testing

**Files:** None new — this is a verification task.

- [ ] **Step 1: Run all tests**

Run: Cmd+U in Xcode.

Expected: All tests pass (8 catalog tests + 4 config tests + template test).

- [ ] **Step 2: Manual test checklist**

Open the app and verify:

- [ ] Settings > Models shows 18 models in 3 sections (LLM, Speech-to-Text, Text-to-Speech)
- [ ] Recommended models appear first in each section with green "Recommended" badge
- [ ] Bundled models (whisper-base, piper-lessac) show as Active/Downloaded, no Download button
- [ ] Non-downloaded models show "Download" button
- [ ] Disk Usage footer shows correct total
- [ ] Onboarding still works (ModelDownloadService from environment)

- [ ] **Step 3: Commit any fixes, then final commit**

```bash
git add -A
git commit -m "feat: Models View redesign — complete implementation"
```
