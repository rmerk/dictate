import Foundation
import Observation
import AppKit
import ApplicationServices
import AVFoundation
import CRCLIEngine

@MainActor
@Observable
final class PermissionService {
    var microphoneGranted: Bool = false
    var accessibilityGranted: Bool = false

    private var pollTimer: Timer?
    private var fastPolling: Bool = false

    func startPolling() {
        checkAll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkAll() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func setFastPolling(_ fast: Bool) {
        guard fast != fastPolling else { return }
        fastPolling = fast
        stopPolling()
        let interval: TimeInterval = fast ? 2.0 : 30.0
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkAll() }
        }
    }

    func checkAll() {
        microphoneGranted = checkMicrophone()
        accessibilityGranted = checkAccessibility()
    }

    func requestMicrophone() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneGranted = granted
        return granted
    }

    func requestAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    private func checkMicrophone() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func checkAccessibility() -> Bool {
        // Use the C API ground-truth check (CGEventTapCreate test) rather than
        // AXIsProcessTrusted(), which is unreliable for unsigned dev builds.
        rcli_hotkey_check_accessibility() != 0
    }
}
