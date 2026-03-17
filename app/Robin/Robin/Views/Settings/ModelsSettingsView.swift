import SwiftUI

struct ModelsSettingsView: View {
    @Environment(EngineService.self) private var engine
    @Environment(ModelDownloadService.self) private var downloads
    @State private var downloadedPaths: Set<String> = []
    @State private var downloadedMetalRTSTTModelIDs: Set<String> = []
    @State private var modelToDelete: ModelCatalogEntry?

    private let modelsDir = NSString(
        string: "~/Library/RCLI/models").expandingTildeInPath

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                modelSection(type: .llm)
                if engine.isUsingMetalRT {
                    metalRTSTTSection
                }
                modelSection(type: .stt)
                modelSection(type: .tts)
            }

            diskUsageFooter
        }
        .task { refreshInstalledState() }
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
        case .stt: engine.selectedOfflineSTTModelId
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
            if type == .stt && !engine.isUsingMetalRT {
                runtimeSTTStatusRow
            }
            ForEach(sorted) { entry in
                modelRow(entry)
            }
            if type == .stt {
                sttSelectionNote
            }
        }
    }

    private var metalRTSTTSection: some View {
        Section("MetalRT Speech-to-Text") {
            runtimeSTTStatusRow

            ForEach(sortedMetalRTSTTEntries) { entry in
                metalRTSTTRow(entry)
            }

            Text(metalRTSTTNoteText)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 2)

            if let errorMessage = engine.metalRTSTTApplyErrorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.vertical, 2)
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
                            .background(.secondary.opacity(0.12))
                            .foregroundColor(.primary)
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
            VStack(alignment: .trailing, spacing: 2) {
                ProgressView(value: progress.fraction)
                    .frame(width: 80)
                if let detailText = progress.detailText {
                    Text(detailText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(Int(progress.fraction * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
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
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func activeView(_ entry: ModelCatalogEntry) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(selectionBadgeTitle(for: entry))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.12))
                    .foregroundColor(.primary)
                    .cornerRadius(4)
                if let detail = selectionDetailText(for: entry) {
                    Text(detail)
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
            Button(selectionButtonTitle(for: entry)) {
                Task { await activateModel(entry) }
            }
            .buttonStyle(.borderedProminent)
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

    @ViewBuilder
    private func metalRTSTTRow(_ entry: MetalRTSTTEntry) -> some View {
        let isRuntimeActive = engine.activeMetalRTSTTModelId == entry.id
        let isSelected = engine.selectedMetalRTSTTModelId == entry.id
        let isDownloaded = downloadedMetalRTSTTModelIDs.contains(entry.id)
        let progress = downloads.activeDownloads[entry.id]

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name).font(.body.bold())
                    if entry.isDefault && !isRuntimeActive {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.12))
                            .foregroundColor(.primary)
                            .cornerRadius(4)
                    }
                    if isSelected && !isRuntimeActive {
                        Text("Selected")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.12))
                            .foregroundColor(.primary)
                            .cornerRadius(4)
                    }
                }
                Text("\(formatSize(entry.sizeBytes)) · \(entry.description)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let progress {
                if progress.failed {
                    failedMetalRTSTTView(entry, message: progress.errorMessage)
                } else {
                    downloadingMetalRTSTTView(entry, progress: progress)
                }
            } else if isRuntimeActive {
                runtimeActiveView
            } else if isDownloaded {
                applyMetalRTSTTButton(entry, isSelected: isSelected)
            } else {
                downloadAndApplyMetalRTSTTButton(entry)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Disk Usage Footer

    private var runtimeSTTStatusRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.activeRuntimeSTTName.isEmpty ? "Unknown" : engine.activeRuntimeSTTName)
                    .font(.body.bold())
                Text(runtimeSTTSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("Runtime")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.12))
                .foregroundColor(.primary)
                .cornerRadius(4)
        }
        .padding(.vertical, 2)
    }

    private var sttSelectionNote: some View {
        Text(sttSelectionNoteText)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.vertical, 2)
    }

    private var diskUsageFooter: some View {
        HStack {
            Text("Disk Usage:")
                .font(.caption)
                .foregroundColor(.secondary)
            let totalBytes = ModelCatalog.all
                .filter { downloadedPaths.contains($0.localPath) }
                .reduce(Int64(0)) { $0 + $1.sizeBytes }
                + MetalRTSTTCatalog.all
                .filter { downloadedMetalRTSTTModelIDs.contains($0.id) }
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
                try await downloads.extractArchive(
                    archivePath: archivePath, to: modelsDir,
                    archiveDirName: entry.archiveDirName,
                    renameTo: entry.localPath)
            }

            refreshInstalledState()
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
            refreshInstalledState()
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
            refreshInstalledState()
        } catch {
            print("Delete failed: \(error)")
        }
    }

    private func startMetalRTSTTDownloadAndApply(_ entry: MetalRTSTTEntry) async {
        do {
            try await downloads.downloadMetalRTSTT(entry)
            refreshInstalledState()
            try await engine.switchMetalRTSTTModel(entry.id)
            refreshInstalledState()
        } catch is CancellationError {
            // User cancelled — already handled by the service.
        } catch {
            print("MetalRT STT apply failed: \(error)")
        }
    }

    private func applyMetalRTSTT(_ entry: MetalRTSTTEntry) async {
        do {
            try await engine.switchMetalRTSTTModel(entry.id)
            refreshInstalledState()
        } catch {
            print("MetalRT STT apply failed: \(error)")
        }
    }

    // MARK: - Helpers

    private func isModelActive(_ entry: ModelCatalogEntry) -> Bool {
        switch entry.type {
        case .llm: return entry.id == engine.activeModelId
        case .stt: return entry.id == engine.selectedOfflineSTTModelId
        case .tts: return entry.id == engine.activeTTSModelId
        }
    }

    private func selectionBadgeTitle(for entry: ModelCatalogEntry) -> String {
        switch entry.type {
        case .stt:
            return "Selected"
        case .llm, .tts:
            return "Active"
        }
    }

    private func selectionDetailText(for entry: ModelCatalogEntry) -> String? {
        switch entry.type {
        case .stt:
            return "Applies on next launch"
        case .tts:
            return "Takes effect on next launch"
        case .llm:
            return nil
        }
    }

    private func selectionButtonTitle(for entry: ModelCatalogEntry) -> String {
        switch entry.type {
        case .stt:
            return "Select"
        case .llm, .tts:
            return "Activate"
        }
    }

    private var runtimeSTTSubtitle: String {
        let engineName = engine.activeEngine.isEmpty ? "engine" : engine.activeEngine
        return "Current runtime via \(engineName)"
    }

    private var sttSelectionNoteText: String {
        if engine.isUsingMetalRT {
            return "Offline STT selection below only affects the non-MetalRT engine. Use the MetalRT section above to change the active Whisper model."
        }

        return "Offline STT selection is saved for the next launch."
    }

    private var metalRTSTTNoteText: String {
        if engine.isApplyingMetalRTSTTSelection,
           let selectedId = engine.selectedMetalRTSTTModelId,
           let entry = MetalRTSTTCatalog.entry(id: selectedId) {
            return "Applying \(entry.name) in the background by restarting the engine."
        }

        if let selectedId = engine.selectedMetalRTSTTModelId,
           let runtimeId = engine.activeMetalRTSTTModelId,
           selectedId != runtimeId,
           let entry = MetalRTSTTCatalog.entry(id: selectedId) {
            return "\(entry.name) is saved in config, but the current runtime model is still shown above."
        }

        return "Selecting a MetalRT STT model updates `metalrt_stt` and restarts the engine in the background."
    }

    private var sortedMetalRTSTTEntries: [MetalRTSTTEntry] {
        MetalRTSTTCatalog.all.sorted { lhs, rhs in
            let lhsRuntime = lhs.id == engine.activeMetalRTSTTModelId
            let rhsRuntime = rhs.id == engine.activeMetalRTSTTModelId
            if lhsRuntime != rhsRuntime { return lhsRuntime }
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.sizeBytes < rhs.sizeBytes
        }
    }

    private var runtimeActiveView: some View {
        Text("Runtime")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.12))
            .foregroundColor(.primary)
            .cornerRadius(4)
    }

    private func applyMetalRTSTTButton(_ entry: MetalRTSTTEntry, isSelected: Bool) -> some View {
        Button(isSelected && engine.metalRTSTTApplyErrorMessage != nil ? "Retry Apply" : "Apply") {
            Task { await applyMetalRTSTT(entry) }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(engine.isApplyingMetalRTSTTSelection)
    }

    private func downloadAndApplyMetalRTSTTButton(_ entry: MetalRTSTTEntry) -> some View {
        Button("Download & Apply") {
            Task { await startMetalRTSTTDownloadAndApply(entry) }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(engine.isApplyingMetalRTSTTSelection)
    }

    private func downloadingMetalRTSTTView(_ entry: MetalRTSTTEntry,
                                           progress: ModelDownloadService.DownloadProgress) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 2) {
                ProgressView(value: progress.fraction)
                    .frame(width: 80)
                Text(progress.detailText ?? "Downloading")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Button {
                downloads.cancelDownload(modelId: entry.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func failedMetalRTSTTView(_ entry: MetalRTSTTEntry, message: String?) -> some View {
        HStack(spacing: 6) {
            Text(message ?? "Download failed")
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(1)
            Button("Retry") {
                Task { await startMetalRTSTTDownloadAndApply(entry) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func refreshInstalledState() {
        let fm = FileManager.default
        var paths = Set<String>()
        for entry in ModelCatalog.all {
            let full = (modelsDir as NSString).appendingPathComponent(entry.localPath)
            if fm.fileExists(atPath: full) {
                paths.insert(entry.localPath)
            }
        }
        downloadedPaths = paths
        downloadedMetalRTSTTModelIDs = MetalRTSTTCatalog.installedIDs(modelsDir: modelsDir)
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 {
            return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
        } else {
            return "\(bytes / 1_000_000) MB"
        }
    }
}
