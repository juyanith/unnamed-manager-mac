import CoreFoundation

/// Two Mission Control settings in System Settings › Desktop & Dock that
/// window actions work best with (S-087). They belong to macOS, not the
/// config file: the app reads and writes the Dock's and Spaces' own preferences.
public enum SpacesSetting: String, CaseIterable, Sendable, Identifiable {
    /// "Automatically rearrange Spaces based on most recent use":
    /// `mru-spaces` in com.apple.dock.
    case rearrangeByRecentUse
    /// "Displays have separate Spaces": `spans-displays` in
    /// com.apple.spaces, which says the opposite.
    case separateSpaces

    public var id: String { rawValue }

    public var domain: String { self == .rearrangeByRecentUse ? "com.apple.dock" : "com.apple.spaces" }
    public var key: String { self == .rearrangeByRecentUse ? "mru-spaces" : "spans-displays" }

    /// The switch the app suggests.
    public var suggestedIsOn: Bool { self == .separateSpaces }

    /// The switch as System Settings shows it, from the key's value. Both
    /// are on when the key isn't set.
    public func isOn(stored: Bool?) -> Bool {
        guard let stored else { return true }
        return self == .separateSpaces ? !stored : stored
    }

    /// The key's value for a switch.
    public func stored(isOn: Bool) -> Bool { self == .separateSpaces ? !isOn : isOn }
}

/// Reads and writes the settings through CFPreferences, as `defaults`
/// does. Tests and snapshots pass a prefix, so they never touch the real
/// Dock and Spaces settings.
public struct SpacesPreferences: Sendable {
    public let domainPrefix: String

    public init(domainPrefix: String = "") { self.domainPrefix = domainPrefix }

    public func domain(_ setting: SpacesSetting) -> String { domainPrefix + setting.domain }

    /// The key's value, or nil when it isn't set.
    public func stored(_ setting: SpacesSetting) -> Bool? {
        let domain = domain(setting) as CFString
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(setting.key as CFString, domain) as? Bool
    }

    public func isOn(_ setting: SpacesSetting) -> Bool { setting.isOn(stored: stored(setting)) }

    /// Writes the switch, and says whether reading it back gives the same.
    @discardableResult
    public func set(_ setting: SpacesSetting, isOn: Bool) -> Bool {
        write(setting, setting.stored(isOn: isOn) as CFBoolean)
        return self.isOn(setting) == isOn
    }

    /// Unsets the key, back to what macOS does by default.
    public func remove(_ setting: SpacesSetting) { write(setting, nil) }

    private func write(_ setting: SpacesSetting, _ value: CFPropertyList?) {
        let domain = domain(setting) as CFString
        CFPreferencesSetAppValue(setting.key as CFString, value, domain)
        CFPreferencesAppSynchronize(domain)
    }
}
