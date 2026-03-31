import SwiftUI

struct PanelView: View {
    @Environment(EngineService.self) private var engine
    @Environment(ConversationStore.self) private var conversation
    @State private var inputText = ""
    @State private var isProcessing = false
    @State private var processingTask: Task<Void, Never>?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            titleBar

            Divider()

            // Messages
            if conversation.messages.isEmpty {
                emptyState
            } else {
                messageList
            }

            Divider()

            // Input bar
            inputBar
        }
        .frame(minWidth: 380, minHeight: 400)
        .task { await consumeToolTraces() }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            Text("RCLI")
                .font(.headline)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(engine.primaryStatusModelLine)
                    .font(.caption)
                if let secondaryLine = engine.secondaryStatusModelLine {
                    Text(secondaryLine)
                        .font(.caption2)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary)
            .cornerRadius(4)
            .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Try saying...")
                .font(.headline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                exampleCommand("Open Safari")
                exampleCommand("Create a note called Ideas")
                exampleCommand("What time is it?")
                exampleCommand("Summarize my clipboard")
            }
            Text("Press ⌘J to speak, or type below")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func exampleCommand(_ text: String) -> some View {
        HStack {
            Image(systemName: "mic.fill")
                .font(.caption)
                .foregroundColor(.blue)
            Text("\"\(text)\"")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(conversation.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: conversation.messages.count) {
                if let last = conversation.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Type a command...", text: $inputText)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .onSubmit { sendTextCommand() }
                .disabled(isProcessing)

            if isProcessing {
                Button {
                    processingTask?.cancel()
                    engine.stopProcessing()
                    isProcessing = false
                    processingTask = nil
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }

            Button {
                inputFocused = true
            } label: {
                Image(systemName: "mic.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundColor(.blue)

            Button {
                sendTextCommand()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundColor(inputText.isEmpty ? .secondary : .blue)
            .disabled(inputText.isEmpty || isProcessing)
        }
        .padding()
    }

    // MARK: - Actions

    private func sendTextCommand() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        conversation.addUserMessage(text, method: .typed)
        isProcessing = true

        processingTask = Task {
            let start = Date()
            do {
                let response = try await engine.processCommand(text)
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                conversation.addAssistantMessage(response, responseTimeMs: ms)
            } catch is CancellationError {
                conversation.addAssistantMessage("Cancelled.")
            } catch {
                conversation.addAssistantMessage("Error: \(error.localizedDescription)")
            }
            isProcessing = false
            processingTask = nil
        }
    }

    private func consumeToolTraces() async {
        for await trace in engine.toolTraceStream {
            if trace.event == "result" {
                conversation.addToolTrace(
                    toolName: trace.toolName,
                    result: trace.data,
                    success: trace.success)
            }
        }
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: ConversationMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Tool traces (above assistant response)
            ForEach(message.toolTraces) { trace in
                HStack(spacing: 4) {
                    Image(systemName: trace.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(trace.success ? .green : .red)
                        .font(.caption)
                    Text("Executed: \(trace.toolName)")
                        .font(.caption)
                        .foregroundStyle(.green)
                    if !trace.result.isEmpty {
                        Text("— \(trace.result)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.green.opacity(0.1))
                .cornerRadius(6)
            }

            // Message content
            HStack(alignment: .top, spacing: 8) {
                // Avatar
                Circle()
                    .fill(message.role == .user ? Color.secondary.opacity(0.3) : Color.blue.opacity(0.2))
                    .frame(width: 24, height: 24)
                    .overlay {
                        Text(message.role == .user ? "U" : "R")
                            .font(.caption2)
                            .foregroundColor(message.role == .user ? .secondary : .blue)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(message.text)
                        .font(.body)
                        .textSelection(.enabled)

                    HStack(spacing: 4) {
                        if let method = message.inputMethod {
                            Image(systemName: method == .voice ? "mic.fill" : "keyboard")
                                .font(.caption2)
                            Text(method == .voice ? "voice" : "typed")
                                .font(.caption2)
                        }
                        if let ms = message.responseTimeMs {
                            Text("\(ms)ms")
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
