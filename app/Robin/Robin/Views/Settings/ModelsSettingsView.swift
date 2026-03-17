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
        let activeId = switch type {
        case .llm: engine.activeModelId
        case .stt: engine.activeSTTModelId
        case .tts: engine.activeTTSModelId
        }
        let sorted = ModelCatalog.models(ofType: type).sorted { a, b in
            let aActive = a.id == activeId
            let bActive = b.id == activeId
            if aActive != bActive { return aActive }
            if a.isRecommended != b.isRecommended { return a.isRecommended }
            return false
        }
        Section(type.displayName) {
            ForEach(sorted) { entry in
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
                    if entry.isRecommended && !isActive {
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
            refreshDownloadedState()
        } catch {
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
