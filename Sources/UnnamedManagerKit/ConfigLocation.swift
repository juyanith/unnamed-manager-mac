import Foundation

/// Where the config file lives. Logic lives in this library so tests can run
/// it without the app. The config model, parser, validator and sequence
/// engine go here too (SPEC.md, Gotchas).
public enum ConfigLocation {
    /// `~/.config/unnamed-manager/config.json`, or the `APP_STORE` override
    /// that tests, snapshots and the self-test use.
    public static func url(environment: [String: String], home: URL) -> URL {
        if let path = environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return home
            .appending(path: ".config/unnamed-manager", directoryHint: .isDirectory)
            .appending(path: "config.json")
    }

    /// True when the config file is an override in /tmp, never the real one.
    public static func isOverridden(environment: [String: String]) -> Bool {
        !(environment["APP_STORE"] ?? "").isEmpty
    }
}
