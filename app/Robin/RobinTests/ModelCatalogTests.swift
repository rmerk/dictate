import Foundation
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
        let match = ModelCatalog.all.first { $0.name == "Liquid LFM2 1.2B Tool" }
        #expect(match?.id == "lfm2-1.2b")
    }

    @Test func activeModelIdNoFalsePositive() {
        let match = ModelCatalog.all.first { $0.name == "Liquid LFM2.5 1.2B Instruct" }
        #expect(match?.id == "lfm2.5-1.2b")
        #expect(match?.id != "lfm2-1.2b")
    }

    @Test func activeModelIdNilForUnknown() {
        let match = ModelCatalog.all.first { $0.name == "Unknown Model XYZ" }
        #expect(match == nil)
    }

    @Test func sttSelectionPrefersPersistedOfflineSelection() {
        let selectionID = ModelSelectionResolver.selectedSTTModelID(
            runtimeSTTName: "Whisper Tiny (MLX 4-bit)",
            persistedOfflineSTTID: "parakeet-tdt"
        )

        #expect(selectionID == "parakeet-tdt")
    }

    @Test func sttSelectionFallsBackToRuntimeNameWhenPersistedSelectionMissing() {
        let selectionID = ModelSelectionResolver.selectedSTTModelID(
            runtimeSTTName: "Whisper base.en",
            persistedOfflineSTTID: nil
        )

        #expect(selectionID == "whisper-base")
    }

    @Test func metalRTSTTCatalogHasExpectedEntries() {
        let ids = MetalRTSTTCatalog.all.map(\.id)
        let localDirectories = MetalRTSTTCatalog.all.map(\.localDirectory)

        #expect(MetalRTSTTCatalog.all.count == 3)
        #expect(ids == [
            "metalrt-whisper-tiny",
            "metalrt-whisper-small",
            "metalrt-whisper-medium",
        ])
        #expect(Set(localDirectories).count == localDirectories.count)
    }

    @Test func metalRTSTTSelectionPrefersPersistedSelection() {
        let selectionID = ModelSelectionResolver.selectedMetalRTSTTModelID(
            runtimeSTTName: "Whisper Tiny (MLX 4-bit)",
            persistedMetalRTSTTID: "metalrt-whisper-medium"
        )

        #expect(selectionID == "metalrt-whisper-medium")
    }

    @Test func metalRTSTTSelectionFallsBackToRuntimeNameWhenPersistedSelectionMissing() {
        let selectionID = ModelSelectionResolver.selectedMetalRTSTTModelID(
            runtimeSTTName: "Whisper Small (MLX 4-bit)",
            persistedMetalRTSTTID: nil
        )

        #expect(selectionID == "metalrt-whisper-small")
    }

    @Test func metalRTSTTInstallRequiresConfigModelAndTokenizerFiles() throws {
        let entry = try #require(MetalRTSTTCatalog.entry(id: "metalrt-whisper-small"))
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let installDirectory = root
            .appendingPathComponent("metalrt", isDirectory: true)
            .appendingPathComponent(entry.localDirectory, isDirectory: true)

        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: installDirectory,
            withIntermediateDirectories: true
        )
        for relativePath in ["config.json", "model.safetensors", "tokenizer.json"] {
            let fileURL = installDirectory.appendingPathComponent(relativePath)
            try Data(relativePath.utf8).write(to: fileURL)
        }

        #expect(MetalRTSTTCatalog.isInstalled(entry, modelsDir: root.path))

        try FileManager.default.removeItem(
            at: installDirectory.appendingPathComponent("tokenizer.json")
        )

        #expect(!MetalRTSTTCatalog.isInstalled(entry, modelsDir: root.path))
    }

    @Test func metalRTWhisperTinyResolvesRootLevelFiles() throws {
        let entry = try #require(MetalRTSTTCatalog.entry(id: "metalrt-whisper-tiny"))
        assertResolvedFileURLs(
            for: entry,
            expectedPaths: [
                "config.json",
                "model.safetensors",
                "tokenizer.json",
            ]
        )
    }

    @Test func metalRTWhisperSmallResolvesFilesFromRepoSubdirectory() throws {
        let entry = try #require(MetalRTSTTCatalog.entry(id: "metalrt-whisper-small"))
        assertResolvedFileURLs(
            for: entry,
            expectedPaths: [
                "whisper-small-mlx-4bit/config.json",
                "whisper-small-mlx-4bit/model.safetensors",
                "whisper-small-mlx-4bit/tokenizer.json",
            ]
        )
    }

    @Test func metalRTWhisperMediumResolvesFilesFromRepoSubdirectory() throws {
        let entry = try #require(MetalRTSTTCatalog.entry(id: "metalrt-whisper-medium"))
        assertResolvedFileURLs(
            for: entry,
            expectedPaths: [
                "whisper-medium-mlx-4bit/config.json",
                "whisper-medium-mlx-4bit/model.safetensors",
                "whisper-medium-mlx-4bit/tokenizer.json",
            ]
        )
    }

    @Test func metalRTDeleteTargetUsesMetalRTSubdirectory() throws {
        let entry = try #require(MetalRTSTTCatalog.entry(id: "metalrt-whisper-small"))
        let target = ModelsSettingsDeleteTarget.metalRTSTT(entry)

        #expect(target.relativePath == "metalrt/\(entry.localDirectory)")
        #expect(target.isDirectory)
    }

    @MainActor
    @Test func deletingMetalRTDirectoryRemovesInstalledState() throws {
        let entry = try #require(MetalRTSTTCatalog.entry(id: "metalrt-whisper-small"))
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let installDirectory = URL(fileURLWithPath: MetalRTSTTCatalog.installDirectory(for: entry, modelsDir: root.path))

        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: installDirectory,
            withIntermediateDirectories: true
        )
        for relativePath in entry.files.map(\.relativePath) {
            let fileURL = installDirectory.appendingPathComponent(relativePath)
            try Data(relativePath.utf8).write(to: fileURL)
        }

        #expect(MetalRTSTTCatalog.installedIDs(modelsDir: root.path).contains(entry.id))

        let downloadService = ModelDownloadService(modelsDir: root.path)
        let deleteTarget = ModelsSettingsDeleteTarget.metalRTSTT(entry)
        try downloadService.deleteModel(
            path: deleteTarget.relativePath,
            isDirectory: deleteTarget.isDirectory
        )

        #expect(!MetalRTSTTCatalog.installedIDs(modelsDir: root.path).contains(entry.id))
    }

    @Test func deletePolicyProtectsActiveAndSelectedModels() throws {
        let offlineSTTEntry = try #require(ModelCatalog.models(ofType: .stt).first)
        let metalRTEntry = try #require(MetalRTSTTCatalog.entry(id: "metalrt-whisper-medium"))

        #expect(
            ModelsSettingsDeletePolicy.isProtected(
                offlineSTTEntry,
                activeModelId: nil,
                selectedOfflineSTTModelId: offlineSTTEntry.id,
                activeTTSModelId: nil
            )
        )
        #expect(
            !ModelsSettingsDeletePolicy.canDelete(
                isInstalled: true,
                isProtected: ModelsSettingsDeletePolicy.isProtected(
                    offlineSTTEntry,
                    activeModelId: nil,
                    selectedOfflineSTTModelId: offlineSTTEntry.id,
                    activeTTSModelId: nil
                )
            )
        )

        #expect(
            ModelsSettingsDeletePolicy.isProtected(
                metalRTEntry,
                runtimeModelId: metalRTEntry.id,
                selectedModelId: nil
            )
        )
        #expect(
            ModelsSettingsDeletePolicy.isProtected(
                metalRTEntry,
                runtimeModelId: nil,
                selectedModelId: metalRTEntry.id
            )
        )
        #expect(
            !ModelsSettingsDeletePolicy.canDelete(
                isInstalled: true,
                isProtected: ModelsSettingsDeletePolicy.isProtected(
                    metalRTEntry,
                    runtimeModelId: nil,
                    selectedModelId: metalRTEntry.id
                )
            )
        )
        #expect(ModelsSettingsDeletePolicy.canDelete(isInstalled: true, isProtected: false))
    }

    @Test func metalRTHidesStandardSTTSection() {
        #expect(!ModelsSettingsSectionPolicy.shouldShowSection(type: .stt, isUsingMetalRT: true))
        #expect(ModelsSettingsSectionPolicy.shouldShowSection(type: .stt, isUsingMetalRT: false))
        #expect(ModelsSettingsSectionPolicy.shouldShowSection(type: .llm, isUsingMetalRT: true))
        #expect(ModelsSettingsSectionPolicy.shouldShowSection(type: .tts, isUsingMetalRT: true))
    }

    @Test func metalRTUsesBeginnerFriendlySpeechRecognitionCopy() {
        #expect(
            ModelsSettingsCopy.sttSectionTitle(isUsingMetalRT: true) == "Speech Recognition"
        )
        #expect(
            ModelsSettingsCopy.sttSectionTitle(isUsingMetalRT: false) == "Speech-to-Text"
        )
        #expect(
            ModelsSettingsCopy.metalRTSTTNoteText(
                isApplyingSelection: false,
                selectedEntryName: nil,
                runtimeEntryName: nil
            ) == "Choose the speech recognition model Robin uses right now."
        )
        #expect(
            ModelsSettingsCopy.metalRTSTTNoteText(
                isApplyingSelection: true,
                selectedEntryName: "Whisper Small",
                runtimeEntryName: nil
            ) == "Robin is switching to Whisper Small in the background."
        )
        #expect(
            ModelsSettingsCopy.metalRTSTTNoteText(
                isApplyingSelection: false,
                selectedEntryName: "Whisper Medium",
                runtimeEntryName: "Whisper Small"
            ) == "Robin will use Whisper Medium after the switch finishes."
        )
    }

    @Test func runtimeSpeechRecognitionCopyIsBeginnerFriendly() {
        #expect(ModelsSettingsCopy.runtimeBadgeTitle == "In Use")
        #expect(
            ModelsSettingsCopy.runtimeSubtitle == "Robin is using this speech recognition model right now."
        )
    }

    private func assertResolvedFileURLs(for entry: MetalRTSTTEntry, expectedPaths: [String]) {
        let actualPaths = entry.files.map { remotePath(in: $0.url) }
        #expect(actualPaths == expectedPaths)
    }

    private func remotePath(in url: URL) -> String {
        let marker = "/resolve/main/"
        let absoluteString = url.absoluteString
        guard let range = absoluteString.range(of: marker) else {
            Issue.record("Unexpected MetalRT file URL: \(absoluteString)")
            return absoluteString
        }
        return String(absoluteString[range.upperBound...])
    }
}
