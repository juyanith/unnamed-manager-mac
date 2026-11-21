import AppKit
import UnnamedManagerKit

/// The Spaces settings the Windows tab suggests and changes (S-087).
/// Snapshots and the self-test use test domains and never restart the Dock.
@MainActor @Observable
final class SpacesSettingsStore {
    private(set) var isOn: [SpacesSetting: Bool] = [:]
    /// Displays Have Separate Spaces as this login uses it: a change waits
    /// until you log out.
    let separateSpacesInEffect: Bool
    /// How many times the Dock was restarted, or would have been in a test.
    private(set) var dockRestarts = 0
    /// Reduce Motion in System Settings › Accessibility › Motion: optional,
    /// so it's never in `unsuggested`. Spaces fade with it instead of
    /// sliding. The app only reads it, since it changes the whole Mac.
    private(set) var reducesMotion = false
    /// What the self-test and snapshots read instead of the Mac's setting.
    @ObservationIgnored var testReducesMotion = false
    @ObservationIgnored let preferences: SpacesPreferences
    @ObservationIgnored private let isTest: Bool

    init(isTest: Bool) {
        self.isTest = isTest
        preferences = SpacesPreferences(domainPrefix: isTest ? "net.unnamed.manager.test." : "")
        if isTest { SpacesSetting.allCases.forEach(preferences.remove) }
        separateSpacesInEffect = isTest ? preferences.isOn(.separateSpaces) : NSScreen.screensHaveSeparateSpaces
        refresh()
        guard !isTest else { return }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Reads them all again, since they can change in System Settings.
    func refresh() {
        for setting in SpacesSetting.allCases { isOn[setting] = preferences.isOn(setting) }
        reducesMotion = isTest ? testReducesMotion : NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// The settings that aren't as suggested.
    var unsuggested: [SpacesSetting] { SpacesSetting.allCases.filter { isOn[$0] != $0.suggestedIsOn } }

    var waitsForLogOut: Bool { isOn[.separateSpaces] != separateSpacesInEffect }

    /// Writes a switch; the Dock reads Rearrange only when it starts.
    func set(_ setting: SpacesSetting, isOn: Bool) {
        if !preferences.set(setting, isOn: isOn) {
            log.error("Spaces: \(setting.key, privacy: .public) in \(setting.domain, privacy: .public) didn't change")
        }
        if setting == .rearrangeByRecentUse { restartDock() }
        refresh()
    }

    private func restartDock() {
        dockRestarts += 1
        guard !isTest else { return }
        // launchd starts the Dock again at once.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        do { try process.run() } catch { log.error("Restart Dock: \(error.localizedDescription, privacy: .public)") }
    }

    static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!
    static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension")!

    /// Under Reduce Motion, what it would change, or that it's on.
    var reduceMotionNote: String {
        reducesMotion
            ? "On, so Spaces fade instead of sliding."
            : "Optional. Turn it on in Accessibility › Motion, and Spaces fade instead of sliding when macOS or the Switch to Desktop fallback changes them. It tones down animations across the Mac too."
    }
}

extension SpacesSetting {
    /// System Settings' words, in title case.
    var title: String {
        switch self {
        case .rearrangeByRecentUse: "Automatically Rearrange Spaces Based on Most Recent Use"
        case .separateSpaces: "Displays Have Separate Spaces"
        }
    }

    var suggestion: String {
        switch self {
        case .rearrangeByRecentUse: "Suggested off, so each Space keeps its place and Control-1, Control-2 and so on always go to the same one."
        case .separateSpaces: "Suggested on, so each display has its own Spaces and switches them on its own."
        }
    }
}
