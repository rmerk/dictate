import SwiftUI

enum ModelsSettingsDeleteTarget: Equatable, Sendable {
    case model(ModelCatalogEntry)
    case metalRTSTT(MetalRTSTTEntry)

    var name: String {
        switch self {
        case .model(let entry):
            entry.name
        case .metalRTSTT(let entry):
            entry.name
        }
    }

    var sizeBytes: Int64 {
        switch self {
        case .model(let entry):
            entry.sizeBytes
        case .metalRTSTT(let entry):
            entry.sizeBytes
        }
    }

    var relativePath: String {
        switch self {
        case .model(let entry):
            entry.localPath
        case .metalRTSTT(let entry):
            "metalrt/\(entry.localDirectory)"
        }
    }

    var isDirectory: Bool {
        switch self {
        case .model(let entry):
            entry.isArchive
        case .metalRTSTT:
            true
        }
    }
}

enum ModelsSettingsDeletePolicy {
    static func isInstalled(_ entry: ModelCatalogEntry, downloadedPaths: Set<String>) -> Bool {
        downloadedPaths.contains(entry.localPath)
    }

    static func isInstalled(_ entry: MetalRTSTTEntry, downloadedModelIDs: Set<String>) -> Bool {
        downloadedModelIDs.contains(entry.id)
    }

    static func isProtected(_ entry: ModelCatalogEntry,
                            activeModelId: String?,
                            selectedOfflineSTTModelId: String?,
                            activeTTSModelId: String?) -> Bool {
        switch entry.type {
        case .llm:
            return entry.id == activeModelId
        case .stt:
            return entry.id == selectedOfflineSTTModelId
        case .tts:
            return entry.id == activeTTSModelId
        }
    }

    static func isProtected(_ entry: MetalRTSTTEntry,
                            runtimeModelId: String?,
                            selectedModelId: String?) -> Bool {
        entry.id == runtimeModelId || entry.id == selectedModelId
    }

    static func canDelete(isInstalled: Bool, isProtected: Bool) -> Bool {
        isInstalled && !isProtected
    }
}

enum ModelsSettingsSectionPolicy {
    static func shouldShowSection(type: ModelType, isUsingMetalRT: Bool) -> Bool {
        !(type == .stt && isUsingMetalRT)
    }
}

enum ModelsSettingsCopy {
    static let runtimeBadgeTitle = "In Use"
    static let runtimeSubtitle = "Robin is using this speech recognition model right now."

    static func sttSectionTitle(isUsingMetalRT: Bool) -> String {
        isUsingMetalRT ? "Speech Recognition" : "Speech-to-Text"
    }

    static func metalRTSTTNoteText(isApplyingSelection: Bool,
                                   selectedEntryName: String?,
                                   runtimeEntryName: String?) -> String {
        if isApplyingSelection, let selectedEntryName {
            return "Robin is switching to \(selectedEntryName) in the background."
        }

        if let selectedEntryName,
           let runtimeEntryName,
           selectedEntryName != runtimeEntryName {
            return "Robin will use \(selectedEntryName) after the switch finishes."
        }

        return "Choose the speech recognition model Robin uses right now."
    }
}

struct ModelsSettingsView: View {
    @Environment(EngineService.self) private var engine
    @Environment(ModelDownloadService.self) private var downloads
    @State private var downloadedPaths: Set<String> = []
    @State private var downloadedMetalRTSTTModelIDs: Set<String> = []
    @State private var pendingDeleteTarget: ModelsSettingsDeleteTarget?

    private let modelsDir = NSString(
        string: "~/Library/RCLI/models").expandingTildeInPath

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                modelSection(type: .llm)
                if engine.isUsingMetalRT {
                    metalRTSTTSection
                }
                if ModelsSettingsSectionPolicy.shouldShowSection(type: .stt, isUsingMetalRT: engine.isUsingMetalRT) {
                    modelSection(type: .stt)
                }
                modelSection(type: .tts)
            }

            diskUsageFooter
        }
        .task { refreshInstalledState() }
        .alert("Delete Model",
               isPresented: Binding(
                   get: { pendingDeleteTarget != nil },
                   set: { if !$0 { pendingDeleteTarget = nil } }
               )) {
            Button("Cancel", role: .cancel) { pendingDeleteTarget = nil }
            Button("Delete", role: .destructive) { deleteModel() }
        } message: {
            if let target = pendingDeleteTarget {
                Text("Delete \(target.name)? This will free \(formatSize(target.sizeBytes)).")
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
        Section(ModelsSettingsCopy.sttSectionTitle(isUsingMetalRT: true)) {
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
        let isProtected = isModelProtected(entry)
        let isDownloaded = isModelInstalled(entry)
        let progress = downloads.activeDownloads[entry.id]

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name).font(.body.bold())
                    if entry.isRecommended && !isProtected {
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
            } else if isProtected {
                activeView(entry)
            } else if isDownloaded {
                downloadedView(entry, deleteTarget: deleteTarget(for: entry))
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
            disabledDeleteButton()
        }
    }

    private func downloadedView(_ entry: ModelCatalogEntry,
                                deleteTarget: ModelsSettingsDeleteTarget?) -> some View {
        HStack(spacing: 8) {
            Button(selectionButtonTitle(for: entry)) {
                Task { await activateModel(entry) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            if let deleteTarget {
                deleteButton {
                    pendingDeleteTarget = deleteTarget
                }
            } else {
                disabledDeleteButton()
            }
        }
    }

    @ViewBuilder
    private func metalRTSTTRow(_ entry: MetalRTSTTEntry) -> some View {
        let isRuntimeActive = engine.activeMetalRTSTTModelId == entry.id
        let isSelected = engine.selectedMetalRTSTTModelId == entry.id
        let isProtected = isMetalRTSTTProtected(entry)
        let isDownloaded = isMetalRTSTTInstalled(entry)
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
                downloadedMetalRTSTTView(
                    entry,
                    isSelected: isSelected,
                    deleteTarget: isProtected ? nil : deleteTarget(for: entry)
                )
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
                Text(ModelsSettingsCopy.runtimeSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(ModelsSettingsCopy.runtimeBadgeTitle)
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
        guard let target = pendingDeleteTarget else { return }
        pendingDeleteTarget = nil
        guard canDelete(target) else { return }

        do {
            try downloads.deleteModel(
                path: target.relativePath,
                isDirectory: target.isDirectory
            )
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

    private func isModelInstalled(_ entry: ModelCatalogEntry) -> Bool {
        ModelsSettingsDeletePolicy.isInstalled(entry, downloadedPaths: downloadedPaths)
    }

    private func isMetalRTSTTInstalled(_ entry: MetalRTSTTEntry) -> Bool {
        ModelsSettingsDeletePolicy.isInstalled(entry, downloadedModelIDs: downloadedMetalRTSTTModelIDs)
    }

    private func isModelProtected(_ entry: ModelCatalogEntry) -> Bool {
        ModelsSettingsDeletePolicy.isProtected(
            entry,
            activeModelId: engine.activeModelId,
            selectedOfflineSTTModelId: engine.selectedOfflineSTTModelId,
            activeTTSModelId: engine.activeTTSModelId
        )
    }

    private func isMetalRTSTTProtected(_ entry: MetalRTSTTEntry) -> Bool {
        ModelsSettingsDeletePolicy.isProtected(
            entry,
            runtimeModelId: engine.activeMetalRTSTTModelId,
            selectedModelId: engine.selectedMetalRTSTTModelId
        )
    }

    private func deleteTarget(for entry: ModelCatalogEntry) -> ModelsSettingsDeleteTarget? {
        let isInstalled = isModelInstalled(entry)
        let isProtected = isModelProtected(entry)
        guard ModelsSettingsDeletePolicy.canDelete(isInstalled: isInstalled, isProtected: isProtected) else {
            return nil
        }
        return .model(entry)
    }

    private func deleteTarget(for entry: MetalRTSTTEntry) -> ModelsSettingsDeleteTarget? {
        let isInstalled = isMetalRTSTTInstalled(entry)
        let isProtected = isMetalRTSTTProtected(entry)
        guard ModelsSettingsDeletePolicy.canDelete(isInstalled: isInstalled, isProtected: isProtected) else {
            return nil
        }
        return .metalRTSTT(entry)
    }

    private func canDelete(_ target: ModelsSettingsDeleteTarget) -> Bool {
        switch target {
        case .model(let entry):
            ModelsSettingsDeletePolicy.canDelete(
                isInstalled: isModelInstalled(entry),
                isProtected: isModelProtected(entry)
            )
        case .metalRTSTT(let entry):
            ModelsSettingsDeletePolicy.canDelete(
                isInstalled: isMetalRTSTTInstalled(entry),
                isProtected: isMetalRTSTTProtected(entry)
            )
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

    private var sttSelectionNoteText: String {
        if engine.isUsingMetalRT {
            return "Offline STT selection below only affects the non-MetalRT engine. Use the MetalRT section above to change the active Whisper model."
        }

        return "Offline STT selection is saved for the next launch."
    }

    private var metalRTSTTNoteText: String {
        ModelsSettingsCopy.metalRTSTTNoteText(
            isApplyingSelection: engine.isApplyingMetalRTSTTSelection,
            selectedEntryName: engine.selectedMetalRTSTTModelId.flatMap { MetalRTSTTCatalog.entry(id: $0)?.name },
            runtimeEntryName: engine.activeMetalRTSTTModelId.flatMap { MetalRTSTTCatalog.entry(id: $0)?.name }
        )
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
        HStack(spacing: 8) {
            Text("Runtime")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.12))
                .foregroundColor(.primary)
                .cornerRadius(4)
            disabledDeleteButton()
        }
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

    private func downloadedMetalRTSTTView(_ entry: MetalRTSTTEntry,
                                          isSelected: Bool,
                                          deleteTarget: ModelsSettingsDeleteTarget?) -> some View {
        HStack(spacing: 8) {
            applyMetalRTSTTButton(entry, isSelected: isSelected)
            if let deleteTarget {
                deleteButton {
                    pendingDeleteTarget = deleteTarget
                }
            } else {
                disabledDeleteButton()
            }
        }
    }

    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "trash")
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func disabledDeleteButton() -> some View {
        Button {
            // Intentionally disabled for protected models.
        } label: {
            Image(systemName: "trash")
                .foregroundColor(.secondary.opacity(0.3))
        }
        .buttonStyle(.plain)
        .disabled(true)
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
