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
    @ObservationIgnored let preferences: SpacesPreferences
    @ObservationIgnored private let isTest: Bool

    init(isTest: Bool) {
        self.isTest = isTest
        preferences = SpacesPreferences(domainPrefix: isTest ? "net.unnamed.manager.test." : "")
        if isTest { SpacesSetting.allCases.forEach(preferences.remove) }
        separateSpacesInEffect = isTest ? preferences.isOn(.separateSpaces) : NSScreen.screensHaveSeparateSpaces
        refresh()
    }

    /// Reads both again, since they can change in System Settings.
    func refresh() {
        for setting in SpacesSetting.allCases { isOn[setting] = preferences.isOn(setting) }
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
