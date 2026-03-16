import Foundation

enum PipelineState: Int {
    case idle = 0
    case listening = 1
    case processing = 2
    case speaking = 3
    case interrupted = 4
}

enum AppLifecycleState {
    case loading
    case ready
    case error(String)
}
