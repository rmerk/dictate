import Foundation
import Observation

@MainActor
@Observable
final class ModelDownloadService: NSObject {
    var activeDownloads: [String: DownloadProgress] = [:]
    var completedDownloads: Set<String> = []

    struct DownloadProgress: Sendable {
        let modelId: String
        let modelName: String
        var bytesWritten: Int64 = 0
        var totalBytes: Int64 = 0
        var fraction: Double { totalBytes > 0 ? Double(bytesWritten) / Double(totalBytes) : 0 }
        var failed: Bool = false
        var errorMessage: String?
    }

    private var session: URLSession!
    private var continuations: [String: CheckedContinuation<Void, Error>] = [:]
    private let modelsDir: String

    init(modelsDir: String = NSString(string: "~/Library/RCLI/models").expandingTildeInPath) {
        self.modelsDir = modelsDir
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "ai.rcli.modeldownload")
        config.isDiscretionary = false
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        // Create models directory
        try? FileManager.default.createDirectory(
            atPath: modelsDir, withIntermediateDirectories: true)
    }

    func download(modelId: String, name: String, url: URL) async throws {
        let task = session.downloadTask(with: url)
        task.taskDescription = modelId
        activeDownloads[modelId] = DownloadProgress(
            modelId: modelId, modelName: name, totalBytes: 0)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            continuations[modelId] = cont
            task.resume()
        }
    }

    func cancelDownload(modelId: String) {
        session.getAllTasks { tasks in
            tasks.first { $0.taskDescription == modelId }?.cancel()
        }
        activeDownloads.removeValue(forKey: modelId)
        if let cont = continuations.removeValue(forKey: modelId) {
            cont.resume(throwing: CancellationError())
        }
    }

    var hasActiveDownloads: Bool { !activeDownloads.isEmpty }
}

extension ModelDownloadService: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        let modelId = downloadTask.taskDescription ?? ""
        let dest = URL(fileURLWithPath: modelsDir)
            .appendingPathComponent(downloadTask.response?.suggestedFilename ?? modelId)

        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)

            Task { @MainActor in
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

    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        let modelId = downloadTask.taskDescription ?? ""
        Task { @MainActor in
            self.activeDownloads[modelId]?.bytesWritten = totalBytesWritten
            self.activeDownloads[modelId]?.totalBytes = totalBytesExpectedToWrite
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error else { return }
        let modelId = task.taskDescription ?? ""
        Task { @MainActor in
            self.activeDownloads[modelId]?.failed = true
            self.activeDownloads[modelId]?.errorMessage = error.localizedDescription
            self.continuations.removeValue(forKey: modelId)?.resume(throwing: error)
        }
    }
}
