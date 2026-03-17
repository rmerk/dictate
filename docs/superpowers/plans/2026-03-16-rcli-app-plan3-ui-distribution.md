# RCLI macOS App — Plan 3: UI & Distribution

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build all user-facing views (conversation panel, settings, onboarding), add model download support, and configure signing/notarization for distribution. End state: a shippable macOS app.

**Architecture:** SwiftUI views consume EngineService via `@Environment`. ModelDownloadService uses URLSession for background downloads. Settings uses SettingsAccess SPM package. Distribution via Developer ID + Hardened Runtime + notarization + Sparkle auto-updates.

**Tech Stack:** SwiftUI (macOS 14+), SettingsAccess (SPM), Sparkle (SPM), URLSession, SMAppService, UserNotifications

**Spec:** `docs/superpowers/specs/2026-03-16-rcli-macos-app-design.md`

**Depends on:** Plan 2 (Services) — EngineService, HotkeyService, OverlayService, PermissionService all working, dictation flow functional

---

## Chunk 1: Conversation Panel

### Task 1: Define conversation data model

**Files:**
- Create: `app/RCLI/State/ConversationStore.swift`

- [ ] **Step 1: Create the conversation model**

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add app/RCLI/State/ConversationStore.swift
git commit -m "feat(app): add ConversationStore — in-memory message model"
```

### Task 2: Build PanelView

**Files:**
- Create: `app/RCLI/Views/PanelView.swift`

- [ ] **Step 1: Create conversation panel**

```swift
import SwiftUI

struct PanelView: View {
    @Environment(EngineService.self) private var engine
    @State private var conversation = ConversationStore()
    @State private var inputText = ""
    @State private var isProcessing = false
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
            Text(engine.activeModel)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary)
                .cornerRadius(4)
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
                .foregroundStyle(.blue)
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
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                // Mic button — trigger capture in panel context
                // For v1, just focus the text field
                inputFocused = true
            } label: {
                Image(systemName: "mic.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            Button {
                sendTextCommand()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(inputText.isEmpty ? .secondary : .blue)
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

        Task {
            let start = Date()
            do {
                let response = try await engine.processCommand(text)
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                conversation.addAssistantMessage(response, responseTimeMs: ms)
            } catch {
                conversation.addAssistantMessage("Error: \(error.localizedDescription)")
            }
            isProcessing = false
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
                            .foregroundStyle(message.role == .user ? .secondary : .blue)
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
```

- [ ] **Step 2: Add Window scene to RCLIApp.swift**

In `app/RCLI/RCLIApp.swift`, add the panel Window scene inside the `body` property, after the `MenuBarExtra`:

```swift
Window("RCLI", id: "panel") {
    PanelView()
        .environment(engine)
}
.defaultSize(width: 420, height: 600)
.windowResizability(.contentMinSize)
```

- [ ] **Step 3: Build and test**

Run the app. Click "Panel" in the menu bar popover (or open the window manually). Type a command and verify the response appears.

- [ ] **Step 4: Commit**

```bash
git add app/RCLI/Views/PanelView.swift app/RCLI/RCLIApp.swift
git commit -m "feat(app): add conversation panel with chat UI, tool traces, and empty state"
```

## Chunk 2: Settings

### Task 3: Add SettingsAccess SPM dependency

**Files:**
- Modify: Xcode project (add package dependency)

- [ ] **Step 1: Add SPM package in Xcode**

1. In Xcode: File → Add Package Dependencies
2. URL: `https://github.com/orchetect/SettingsAccess`
3. Version: Up to Next Major
4. Add to RCLI target

- [ ] **Step 2: Verify build**

Build to confirm the package resolves and links.

- [ ] **Step 3: Commit**

```bash
git add app/RCLI.xcodeproj
git commit -m "build(app): add SettingsAccess SPM dependency"
```

### Task 4: Build SettingsView with 5 tabs

**Files:**
- Create: `app/RCLI/Views/SettingsView.swift`
- Create: `app/RCLI/Views/Settings/GeneralSettingsView.swift`
- Create: `app/RCLI/Views/Settings/ModelsSettingsView.swift`
- Create: `app/RCLI/Views/Settings/HotkeysSettingsView.swift`
- Create: `app/RCLI/Views/Settings/ActionsSettingsView.swift`
- Create: `app/RCLI/Views/Settings/AdvancedSettingsView.swift`

- [ ] **Step 1: Create SettingsView container**

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            ModelsSettingsView()
                .tabItem { Label("Models", systemImage: "cpu") }
            HotkeysSettingsView()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            ActionsSettingsView()
                .tabItem { Label("Actions", systemImage: "bolt.fill") }
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }
        .frame(width: 500, height: 400)
    }
}
```

- [ ] **Step 2: Create GeneralSettingsView**

```swift
import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @Environment(EngineService.self) private var engine
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var selectedPersonality = "default"
    @State private var outputMode = "both"

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue // revert
                        }
                    }
            }

            Section("Personality") {
                Picker("Voice personality", selection: $selectedPersonality) {
                    Text("Default").tag("default")
                    Text("Professional").tag("professional")
                    Text("Quirky").tag("quirky")
                    Text("Cynical").tag("cynical")
                    Text("Nerdy").tag("nerdy")
                }
                .onChange(of: selectedPersonality) { _, newValue in
                    try? engine.setPersonality(newValue)
                }
            }

            Section("Output") {
                Picker("Response mode", selection: $outputMode) {
                    Text("Text only").tag("text")
                    Text("Voice only").tag("voice")
                    Text("Both").tag("both")
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

- [ ] **Step 3: Create ModelsSettingsView**

```swift
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
                    // TODO: ModelDownloadService (Task 7)
                }
                .controlSize(.small)
            }
        }
    }
}
```

- [ ] **Step 4: Create HotkeysSettingsView**

```swift
import SwiftUI

struct HotkeysSettingsView: View {
    @Environment(HotkeyService.self) private var hotkey
    @State private var dictationHotkey = "⌘J"

    var body: some View {
        Form {
            Section("Dictation") {
                HStack {
                    Text("Dictation hotkey")
                    Spacer()
                    Text(dictationHotkey)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.quaternary)
                        .cornerRadius(6)
                        .font(.system(.body, design: .monospaced))
                }
                Text("⌘J is also used by Safari for Downloads. Choose a different shortcut if this conflicts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                HStack {
                    Text("Hotkey listener")
                    Spacer()
                    Image(systemName: hotkey.isListening ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(hotkey.isListening ? .green : .red)
                    Text(hotkey.isListening ? "Active" : "Inactive")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

Note: A full key recorder widget is a v2 enhancement. For v1, the hotkey is displayed but not reconfigurable from the UI (users can edit `~/Library/RCLI/config` manually, matching existing CLI behavior).

- [ ] **Step 5: Create ActionsSettingsView**

```swift
import SwiftUI

struct ActionsSettingsView: View {
    @Environment(EngineService.self) private var engine
    @State private var actions: [ActionInfo] = []
    @State private var showCustomize = false
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading) {
            // Category toggles (default view)
            Form {
                Section {
                    HStack {
                        Text("Enabled actions")
                        Spacer()
                        Text("\(engine.enabledActionCount)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("Enable All") { engine.resetActionsToDefaults() }
                        Button("Disable All") { engine.disableAllActions() }
                    }
                }

                DisclosureGroup("Customize individual actions", isExpanded: $showCustomize) {
                    if actions.isEmpty {
                        ProgressView()
                    } else {
                        TextField("Search actions...", text: $searchText)

                        ForEach(filteredActions) { action in
                            Toggle(isOn: Binding(
                                get: { engine.isActionEnabled(action.name) },
                                set: { engine.setActionEnabled(action.name, enabled: $0) }
                            )) {
                                VStack(alignment: .leading) {
                                    Text(action.name).font(.body)
                                    if !action.description.isEmpty {
                                        Text(action.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding()
        .task {
            actions = await engine.listActions()
        }
    }

    private var filteredActions: [ActionInfo] {
        if searchText.isEmpty { return actions }
        return actions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }
}
```

- [ ] **Step 6: Create AdvancedSettingsView**

```swift
import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(PermissionService.self) private var permissions
    @State private var performanceMode = "balanced"

    var body: some View {
        Form {
            Section("Performance") {
                Picker("Mode", selection: $performanceMode) {
                    Text("Battery Saver").tag("battery")
                    Text("Balanced").tag("balanced")
                    Text("Maximum Quality").tag("quality")
                }
                .pickerStyle(.segmented)
                Text(performanceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                PermissionRow(
                    name: "Microphone",
                    granted: permissions.microphoneGranted,
                    action: { permissions.openMicrophoneSettings() }
                )
                PermissionRow(
                    name: "Accessibility",
                    granted: permissions.accessibilityGranted,
                    action: { permissions.requestAccessibility() }
                )
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var performanceDescription: String {
        switch performanceMode {
        case "battery": return "Uses fewer GPU layers. Lower quality, longer battery life."
        case "quality": return "Uses all GPU layers. Best quality, higher power usage."
        default: return "Default GPU settings. Good balance of quality and efficiency."
        }
    }
}

struct PermissionRow: View {
    let name: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Granted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Open Settings") { action() }
                    .controlSize(.small)
            }
        }
    }
}
```

- [ ] **Step 7: Add Settings scene to RCLIApp.swift**

Add after the Window scene:

```swift
Settings {
    SettingsView()
        .environment(engine)
        .environment(hotkey)
        .environment(permissions)
}
```

- [ ] **Step 8: Build, test, commit**

```bash
mkdir -p app/RCLI/Views/Settings
git add app/RCLI/Views/SettingsView.swift app/RCLI/Views/Settings/
git add app/RCLI/RCLIApp.swift
git commit -m "feat(app): add Settings with 5 tabs — General, Models, Hotkeys, Actions, Advanced"
```

## Chunk 3: Onboarding & Model Downloads

### Task 5: ModelDownloadService

**Files:**
- Create: `app/RCLI/Services/ModelDownloadService.swift`

- [ ] **Step 1: Create download service**

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add app/RCLI/Services/ModelDownloadService.swift
git commit -m "feat(app): add ModelDownloadService — URLSession background downloads with progress"
```

### Task 6: Build OnboardingView

**Files:**
- Create: `app/RCLI/Views/OnboardingView.swift`

- [ ] **Step 1: Create onboarding wizard**

```swift
import SwiftUI

struct OnboardingView: View {
    @Environment(EngineService.self) private var engine
    @Environment(PermissionService.self) private var permissions
    @Binding var isPresented: Bool

    @State private var currentStep = 0
    @State private var selectedModel: String? = "qwen3-0.6b"
    @State private var downloadService = ModelDownloadService()
    @State private var downloadStarted = false

    private let steps = ["Welcome", "Models", "Permissions", "Hotkey"]

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            StepIndicator(steps: steps, currentStep: currentStep)
                .padding()

            Divider()

            // Content
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: modelsStep
                case 2: permissionsStep
                case 3: hotkeyStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()

            Divider()

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") { currentStep -= 1 }
                }
                Spacer()
                if currentStep < steps.count - 1 {
                    Button("Skip") { currentStep += 1 }
                        .foregroundStyle(.secondary)
                    Button("Continue") { advance() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Done") { finishOnboarding() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 560, height: 420)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            Text("RCLI")
                .font(.largeTitle.bold())
            Text("Private, Local AI Assistant")
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                FeatureCard(icon: "mic.fill", title: "Voice Commands", subtitle: "Hands-Free Control")
                FeatureCard(icon: "pencil.line", title: "Dictation", subtitle: "Super Fast Typing")
                FeatureCard(icon: "lock.fill", title: "Private", subtitle: "100% On-Device")
            }
        }
    }

    private var modelsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RCLI needs AI models to work locally.")
                .font(.headline)
            Text("Choose one to download:")
                .foregroundStyle(.secondary)

            // Model cards
            ModelCard(id: "qwen3-0.6b", name: "Qwen3 0.6B",
                      detail: "Fast responses, 456 MB", tag: "Recommended",
                      selected: selectedModel == "qwen3-0.6b") {
                selectedModel = "qwen3-0.6b"
            }
            ModelCard(id: "qwen3.5-2b", name: "Qwen3.5 2B",
                      detail: "Smarter, 1.5 GB", tag: nil,
                      selected: selectedModel == "qwen3.5-2b") {
                selectedModel = "qwen3.5-2b"
            }

            // Download progress
            if let modelId = selectedModel,
               let progress = downloadService.activeDownloads[modelId] {
                ProgressView(value: progress.fraction) {
                    Text("Downloading... \(Int(progress.fraction * 100))%")
                        .font(.caption)
                }
                if progress.failed {
                    HStack {
                        Text(progress.errorMessage ?? "Download failed")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Button("Retry") { startDownload() }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RCLI needs two permissions:")
                .font(.headline)

            PermissionCard(
                icon: "mic.fill",
                name: "Microphone",
                description: "Needed to hear your voice commands and dictation.",
                granted: permissions.microphoneGranted,
                action: { Task { await permissions.requestMicrophone() } }
            )

            PermissionCard(
                icon: "hand.raised.fill",
                name: "Accessibility",
                description: "Needed for the global keyboard shortcut and pasting text. RCLI does not log or record any keystrokes.",
                granted: permissions.accessibilityGranted,
                action: { permissions.requestAccessibility() }
            )
        }
    }

    private var hotkeyStep: some View {
        VStack(spacing: 20) {
            Text("Set your dictation shortcut")
                .font(.headline)

            Text("⌘J")
                .font(.system(size: 36, design: .monospaced))
                .padding(20)
                .background(.quaternary)
                .cornerRadius(12)

            Text("Press ⌘J anywhere to start dictating.")
                .foregroundStyle(.secondary)
            Text("You can change this anytime in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    private func advance() {
        if currentStep == 1 && !downloadStarted {
            startDownload()
        }
        currentStep += 1
    }

    private func startDownload() {
        guard let modelId = selectedModel else { return }
        downloadStarted = true
        // TODO: get actual URL from model registry via rcli_list_available_models
        // For now, use a placeholder — the real URL comes from the C API
        Task {
            do {
                let models = try await engine.listAvailableModels()
                // Find URL for selected model and download
                // Implementation depends on model registry exposing download URLs
            } catch { /* handle */ }
        }
    }

    private func finishOnboarding() {
        NSApp.setActivationPolicy(.accessory)
        isPresented = false

        // Send notification
        Task {
            let content = UNMutableNotificationContent()
            content.title = "You're all set!"
            content.body = "Press ⌘J anywhere to start dictating."
            let request = UNNotificationRequest(
                identifier: "onboarding-complete",
                content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}

// MARK: - Supporting Views

struct StepIndicator: View {
    let steps: [String]
    let currentStep: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, name in
                HStack(spacing: 4) {
                    Circle()
                        .fill(index <= currentStep ? Color.blue : Color.secondary.opacity(0.3))
                        .frame(width: 24, height: 24)
                        .overlay {
                            if index < currentStep {
                                Image(systemName: "checkmark")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                            } else {
                                Text("\(index + 1)")
                                    .font(.caption2)
                                    .foregroundStyle(index == currentStep ? .white : .secondary)
                            }
                        }
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(index == currentStep ? .primary : .secondary)
                }
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(index < currentStep ? Color.blue : Color.secondary.opacity(0.3))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct FeatureCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
            Text(title).font(.caption.bold())
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 120, height: 80)
        .background(.quaternary)
        .cornerRadius(8)
    }
}

struct ModelCard: View {
    let id: String
    let name: String
    let detail: String
    let tag: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text(name).font(.body.bold())
                        if let tag {
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.2))
                                .foregroundStyle(.green)
                                .cornerRadius(4)
                        }
                    }
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding()
            .background(.quaternary)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.blue : Color.clear, lineWidth: 2)
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct PermissionCard: View {
    let icon: String
    let name: String
    let description: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.body.bold())
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else {
                Button("Grant") { action() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding()
        .background(.quaternary)
        .cornerRadius(8)
    }
}
```

- [ ] **Step 2: Wire onboarding into RCLIApp**

Add `@AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false` and `@State private var showOnboarding = false` to `RCLIApp`. In the `startApp()` function, check `!hasCompletedOnboarding` and set `showOnboarding = true`. Add a `.sheet(isPresented: $showOnboarding)` modifier on the MenuBarExtra content showing `OnboardingView(isPresented: $showOnboarding)`.

When onboarding finishes, set `hasCompletedOnboarding = true`.

- [ ] **Step 3: Build, test onboarding flow**

Launch the app for the first time (or reset `hasCompletedOnboarding` in UserDefaults). Verify all 4 steps display correctly and navigation works.

- [ ] **Step 4: Commit**

```bash
git add app/RCLI/Views/OnboardingView.swift app/RCLI/RCLIApp.swift
git commit -m "feat(app): add 4-step onboarding wizard with model selection and permission requests"
```

## Chunk 4: Distribution

### Task 7: Add Sparkle SPM dependency

**Files:**
- Modify: Xcode project

- [ ] **Step 1: Add Sparkle in Xcode**

1. File → Add Package Dependencies
2. URL: `https://github.com/sparkle-project/Sparkle`
3. Version: Up to Next Major (2.x)
4. Add `Sparkle` framework to RCLI target

- [ ] **Step 2: Add SUFeedURL to Info.plist**

Add to `app/RCLI/Info.plist`:

```xml
<key>SUFeedURL</key>
<string>https://updates.runanywhere.ai/rcli/appcast.xml</string>
```

Note: Replace the URL with the actual appcast URL when ready. For development, this can be a placeholder.

- [ ] **Step 3: Add update check to SettingsView**

In `GeneralSettingsView`, add a "Check for Updates" button using Sparkle's `SPUStandardUpdaterController`:

```swift
import Sparkle

// In GeneralSettingsView body, add to the Startup section:
Button("Check for Updates...") {
    SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        .checkForUpdates(nil)
}
```

- [ ] **Step 4: Commit**

```bash
git add app/RCLI.xcodeproj app/RCLI/Info.plist app/RCLI/Views/Settings/GeneralSettingsView.swift
git commit -m "build(app): add Sparkle for auto-updates"
```

### Task 8: Configure signing and notarization

This task documents the manual Xcode configuration and a notarization script. No code changes.

- [ ] **Step 1: Configure code signing in Xcode**

1. Select RCLI target → Signing & Capabilities
2. Team: select your Apple Developer account
3. Signing Certificate: Developer ID Application
4. Enable Hardened Runtime (should already be on)
5. Verify Entitlements.plist is set correctly

- [ ] **Step 2: Create notarization script**

Create `scripts/notarize.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Notarize RCLI.app for distribution
# Usage: bash scripts/notarize.sh path/to/RCLI.app
#
# Requires:
#   APPLE_ID — your Apple ID email
#   APPLE_TEAM_ID — your team ID
#   APPLE_APP_PASSWORD — app-specific password

APP_PATH="${1:?Usage: notarize.sh path/to/RCLI.app}"
APP_NAME="$(basename "$APP_PATH" .app)"

echo "=== Zipping for notarization ==="
ZIP_PATH="/tmp/${APP_NAME}.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "=== Submitting to Apple ==="
xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APPLE_APP_PASSWORD}" \
    --wait

echo "=== Stapling ==="
xcrun stapler staple "$APP_PATH"

echo "=== Done ==="
echo "Notarized: $APP_PATH"
rm "$ZIP_PATH"
```

- [ ] **Step 3: Make executable and commit**

```bash
chmod +x scripts/notarize.sh
git add scripts/notarize.sh
git commit -m "build: add notarization script for non-App Store distribution"
```

### Task 9: Add .superpowers to .gitignore and final cleanup

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Update .gitignore**

Add:

```
# Brainstorm sessions
.superpowers/

# Xcode
app/RCLI.xcodeproj/project.xcworkspace/xcuserdata/
app/RCLI.xcodeproj/xcuserdata/
DerivedData/
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: add .superpowers and Xcode user data to .gitignore"
```

---

## Verification Checklist

After completing all tasks:

- [ ] Conversation panel opens (⌘⇧J or menu bar button) and shows empty state
- [ ] Typing a command in the panel shows the response with timing
- [ ] Tool traces appear inline as green badges
- [ ] Settings opens with all 5 tabs populated
- [ ] General: Launch at login toggle works (SMAppService)
- [ ] Models: lists available models with download status
- [ ] Hotkeys: shows current hotkey and listener status
- [ ] Actions: category view with "Customize" disclosure working
- [ ] Advanced: permissions status, performance picker
- [ ] Onboarding appears on first launch with all 4 steps
- [ ] Model download starts and shows progress
- [ ] Permission requests open correct System Settings panes
- [ ] Post-onboarding notification fires
- [ ] Sparkle "Check for Updates" doesn't crash (even without a real appcast)
- [ ] App builds with Hardened Runtime
- [ ] Notarization script runs (with valid credentials)
- [ ] All dictation functionality from Plan 2 still works

## What's Next

The app is shippable after this plan. Future work (v2):
- XPC Service extraction (Phase 2 architecture)
- Conversation persistence
- Key recorder widget for hotkey customization
- RAG UI
- Full Voice Mode UI
- Accessibility audit (VoiceOver, keyboard nav)
