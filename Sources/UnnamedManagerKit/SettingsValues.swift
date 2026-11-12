import Foundation

/// Rules for values typed in Settings (S-032).
public enum SettingsValues {
    /// A delay or timeout in milliseconds: never below zero, at most a minute.
    public static func milliseconds(_ value: Int) -> Int {
        min(max(0, value), 60_000)
    }
}
