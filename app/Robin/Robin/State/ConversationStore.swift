import Foundation
import Observation

struct ConversationMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    let inputMethod: InputMethod?
    let timestamp: Date
    var toolTraces: [ToolTrace]
    var responseTimeMs: Int?

    enum Role { case user, assistant }
    enum InputMethod { case voice, typed }

    struct ToolTrace: Identifiable {
        let id = UUID()
        let toolName: String
        let result: String
        let success: Bool
    }
}

@MainActor
@Observable
final class ConversationStore {
    var messages: [ConversationMessage] = []

    func addUserMessage(_ text: String, method: ConversationMessage.InputMethod) {
        messages.append(ConversationMessage(
            role: .user, text: text, inputMethod: method,
            timestamp: Date(), toolTraces: []))
    }

    func addAssistantMessage(_ text: String, responseTimeMs: Int? = nil) {
        messages.append(ConversationMessage(
            role: .assistant, text: text, inputMethod: nil,
            timestamp: Date(), toolTraces: [], responseTimeMs: responseTimeMs))
    }

    func addToolTrace(toolName: String, result: String, success: Bool) {
        guard !messages.isEmpty else { return }
        messages[messages.count - 1].toolTraces.append(
            ConversationMessage.ToolTrace(
                toolName: toolName, result: result, success: success))
    }

    func clear() { messages.removeAll() }
}
