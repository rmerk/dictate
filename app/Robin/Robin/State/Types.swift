import Foundation

// Pipeline state matching C API enum values
enum PipelineState: Int, Sendable {
    case idle = 0
    case listening = 1
    case processing = 2
    case speaking = 3
    case interrupted = 4
}

// App lifecycle (independent of pipeline)
enum AppLifecycleState: Sendable {
    case loading
    case ready
    case error(String)
}

// Callback event types
struct TranscriptEvent: Sendable {
    let text: String
    let isFinal: Bool
}

struct ToolTraceEvent: Sendable {
    let event: String    // "detected" or "result"
    let toolName: String
    let data: String
    let success: Bool
}

// Model type (shared by ModelInfo and ModelCatalogEntry)
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

struct MetalRTModelFile: Equatable, Sendable {
    let relativePath: String
    let url: URL
}

struct MetalRTSTTEntry: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let sizeBytes: Int64
    let description: String
    let hfRepo: String
    let hfSubdirectory: String?
    let localDirectory: String
    let isDefault: Bool

    var files: [MetalRTModelFile] {
        Self.requiredFiles.map(makeRemoteFile)
    }

    private func makeRemoteFile(relativePath: String) -> MetalRTModelFile {
        let remotePath: String
        if let hfSubdirectory, !hfSubdirectory.isEmpty {
            remotePath = "\(hfSubdirectory)/\(relativePath)"
        } else {
            remotePath = relativePath
        }

        return MetalRTModelFile(
            relativePath: relativePath,
            url: Self.resolveHuggingFaceURL(repo: hfRepo, remotePath: remotePath)
        )
    }

    private static func resolveHuggingFaceURL(repo: String, remotePath: String) -> URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(remotePath)")!
    }

    private static let requiredFiles = [
        "config.json",
        "model.safetensors",
        "tokenizer.json",
    ]
}

// Model info (from rcli_list_available_models JSON)
struct ModelInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let sizeBytes: Int64
    let type: ModelType
    let isDownloaded: Bool
}

// Action info (from rcli_action_list JSON)
struct ActionInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let category: String
    let isEnabled: Bool
}

// Permission types
enum Permission: String, Sendable {
    case microphone
    case accessibility
}

// Hotkey routing mode
enum HotkeyRoutingMode: String, Sendable {
    case auto    // heuristic decides dictate vs command
    case manual  // two explicit hotkeys
}

// Result of the auto-router
enum HotkeyMode: Sendable {
    case dictate
    case command
}

/// Lightweight heuristic router — runs in ~0 ms, no LLM involved.
/// Returns .command if the transcript starts with a known action verb
/// and at least one action is enabled; otherwise .dictate.
enum HotkeyRouter {
    private static let commandVerbs: Set<String> = [
        "open", "close", "create", "send", "search", "find",
        "play", "pause", "stop", "set", "show", "hide",
        "type", "click", "move", "copy", "summarize", "translate",
        "what", "who", "when", "where", "why", "how",
        "turn", "enable", "disable", "launch", "quit", "switch",
        "increase", "decrease", "mute", "unmute", "take", "make",
        "add", "delete", "remove", "schedule", "remind", "check"
    ]

    static func route(_ text: String, enabledActionCount: Int) -> HotkeyMode {
        guard enabledActionCount > 0, !text.isEmpty else { return .dictate }
        let firstWord = text.lowercased().split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        return commandVerbs.contains(firstWord) ? .command : .dictate
    }
}

// Errors
enum RCLIError: LocalizedError, Sendable {
    case initFailed(String)
    case modelNotFound(String)
    case modelLoadFailed(String)
    case permissionDenied(Permission)
    case engineNotReady
    case commandFailed(String)
    case transcriptionFailed
    case ragIngestFailed(String)
    case speakFailed

    var errorDescription: String? {
        switch self {
        case .initFailed(let msg): return "Engine init failed: \(msg)"
        case .modelNotFound(let id): return "Model not found: \(id)"
        case .modelLoadFailed(let id): return "Failed to load model: \(id)"
        case .permissionDenied(let p): return "\(p.rawValue) permission denied"
        case .engineNotReady: return "Engine not initialized"
        case .commandFailed(let msg): return "Command failed: \(msg)"
        case .transcriptionFailed: return "Transcription failed"
        case .ragIngestFailed(let msg): return "RAG ingest failed: \(msg)"
        case .speakFailed: return "TTS playback failed"
        }
    }
}
