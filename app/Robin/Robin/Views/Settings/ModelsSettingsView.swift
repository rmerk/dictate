import SwiftUI

struct ModelsSettingsView: View {
    @Environment(EngineService.self) private var engine
    @State private var models: [ModelInfo] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                ProgressView("Loading models...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("LLM") {
                        ForEach(models.filter { $0.type == .llm }) { model in
                            ModelRow(model: model, isActive: model.name == engine.activeModel)
                        }
                    }
                    Section("STT & TTS") {
                        ForEach(models.filter { $0.type == .stt || $0.type == .tts }) { model in
                            let isActive = model.name == engine.activeSTTModel ||
                                           model.name == engine.activeTTSModel
                            ModelRow(model: model, isActive: isActive)
                        }
                    }
                }

                // Disk usage
                HStack {
                    Text("Disk Usage:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    let totalMB = models.filter(\.isDownloaded)
                        .reduce(0) { $0 + $1.sizeBytes } / 1_000_000
                    Text("\(totalMB) MB")
                        .font(.caption)
                    Spacer()
                }
                .padding()
            }
        }
        .task {
            do {
                models = try await engine.listAvailableModels()
            } catch { /* empty list */ }
            isLoading = false
        }
    }
}

struct ModelRow: View {
    let model: ModelInfo
    let isActive: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(model.name).font(.body)
                Text("\(model.sizeBytes / 1_000_000) MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Text("Active")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .cornerRadius(4)
            } else if model.isDownloaded {
                Text("Downloaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Download") {
                    // TODO: ModelDownloadService integration
                }
                .controlSize(.small)
            }
        }
    }
}
