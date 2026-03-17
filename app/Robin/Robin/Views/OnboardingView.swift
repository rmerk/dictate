import SwiftUI
import UserNotifications

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
        Task {
            do {
                let models = try await engine.listAvailableModels()
                // Find URL for selected model and download
                // Implementation depends on model registry exposing download URLs
                _ = models // suppress unused warning
                _ = modelId
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
