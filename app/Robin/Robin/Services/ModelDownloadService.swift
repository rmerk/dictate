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
    private var destinationFilenames: [String: String] = [:]
    private let modelsDir: String

    init(modelsDir: String = NSString(string: "~/Library/RCLI/models").expandingTildeInPath) {
        self.modelsDir = modelsDir
        super.init()
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        // Create models directory
        try? FileManager.default.createDirectory(
            atPath: modelsDir, withIntermediateDirectories: true)
    }

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

    func cancelDownload(modelId: String) {
        activeDownloads.removeValue(forKey: modelId)
        destinationFilenames.removeValue(forKey: modelId)
        session.getAllTasks { tasks in
            tasks.first { $0.taskDescription == modelId }?.cancel()
        }
        // Do NOT resume continuation here — let didCompleteWithError handle it
        // with NSURLErrorCancelled. This prevents double-resume crashes.
    }

    func extractArchive(archivePath: String, to directory: String,
                        archiveDirName: String?, renameTo localPath: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
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
                        cont.resume(throwing: RCLIError.commandFailed(
                            "Archive extraction failed (exit \(process.terminationStatus))"))
                        return
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
                        cont.resume(throwing: RCLIError.commandFailed(
                            "Extracted directory not found: \(localPath)"))
                        return
                    }

                    // Only delete archive after verified extraction
                    try? FileManager.default.removeItem(atPath: archivePath)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func deleteModel(path: String, isDirectory: Bool) throws {
        let fullPath = (modelsDir as NSString).appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: fullPath) else { return }
        try FileManager.default.removeItem(atPath: fullPath)
    }

    var hasActiveDownloads: Bool { !activeDownloads.isEmpty }
}

extension ModelDownloadService: URLSessionDownloadDelegate {
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
