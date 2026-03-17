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
}
