import Testing
import AppKit
@testable import Robin

struct RobinTests {
    @MainActor
    @Test func presentSettingsPromotesAppBeforeOpeningWindow() {
        var events: [String] = []
        defer { SettingsWindowCoordinator.restoreMenuBarMode() }

        SettingsWindowCoordinator.presentSettings(
            setActivationPolicy: { policy in
                events.append(policy == .regular ? "regular" : "other")
            },
            activate: { ignoringOtherApps in
                events.append("activate:\(ignoringOtherApps)")
            },
            openSettings: {
                events.append("open")
            }
        )

        #expect(events == ["regular", "activate:true", "open"])
    }

    @MainActor
    @Test func closingSettingsRestoresAccessoryMode() {
        var events: [String] = []

        SettingsWindowCoordinator.presentSettings(
            setActivationPolicy: { _ in },
            activate: { _ in },
            openSettings: { }
        )

        SettingsWindowCoordinator.restoreMenuBarMode {
            events.append($0 == .accessory ? "accessory" : "other")
        }

        #expect(events == ["accessory"])
    }

    @MainActor
    @Test func closingSettingsKeepsRegularModeWhileOnboardingIsVisible() {
        var events: [String] = []

        SettingsWindowCoordinator.beginOnboardingPresentation(
            setActivationPolicy: { policy in
                events.append(policy == .regular ? "regular" : "other")
            },
            activate: { _ in }
        )

        SettingsWindowCoordinator.presentSettings(
            setActivationPolicy: { policy in
                events.append(policy == .regular ? "regular" : "other")
            },
            activate: { _ in },
            openSettings: { }
        )

        SettingsWindowCoordinator.restoreMenuBarMode {
            events.append($0 == .accessory ? "accessory" : "other")
        }

        SettingsWindowCoordinator.endOnboardingPresentation {
            events.append($0 == .accessory ? "accessory" : "other")
        }

        #expect(events == ["regular", "accessory"])
    }

    @MainActor
    @Test func refocusOnlyRunsWhileRobinIsStillActive() {
        let window = NSWindow()
        window.title = "Settings"

        #expect(SettingsWindowCoordinator.shouldRefocusSettingsWindow(window, appIsActive: true))
        #expect(!SettingsWindowCoordinator.shouldRefocusSettingsWindow(window, appIsActive: false))
    }

    @MainActor
    @Test func endingOnboardingPresentationTwiceIsSafe() {
        var events: [String] = []

        SettingsWindowCoordinator.beginOnboardingPresentation(
            setActivationPolicy: { policy in
                events.append(policy == .regular ? "regular" : "other")
            },
            activate: { _ in }
        )

        SettingsWindowCoordinator.endOnboardingPresentation {
            events.append($0 == .accessory ? "accessory" : "other")
        }

        SettingsWindowCoordinator.endOnboardingPresentation {
            events.append($0 == .accessory ? "accessory" : "other")
        }

        #expect(events == ["regular", "accessory"])
    }
}
