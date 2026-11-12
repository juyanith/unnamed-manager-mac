import AppKit
import UnnamedManagerKit

/// Icons for the Guide's rows: apps (S-054), files, folders and URLs (S-055),
/// and SF Symbols (S-056).
/// Filled when the config loads, so showing the Guide only reads what is
/// already here.
@MainActor
final class GuideIcons {
    static let shared = GuideIcons()

    /// Found icons only.
    private var icons: [IconSource: NSImage] = [:]
    /// How many times an icon was looked up, for the self-test.
    private(set) var lookups = 0

    /// The icon, if it was found when looked up.
    func icon(for source: IconSource) -> NSImage? {
        icons[source]
    }

    /// The icon, looked up now if it wasn't found yet: for the Bindings
    /// editor's preview, never the Guide.
    func lookUpIcon(for source: IconSource) -> NSImage? {
        load([source])
        return icons[source]
    }

    /// Looks up the icons not found yet. A missing app or file is tried
    /// again on the next load, in case it exists by then.
    func load(_ sources: Set<IconSource>) {
        for source in sources where icons[source] == nil {
            lookups += 1
            icons[source] = Self.lookUp(source)
        }
    }

    private static func lookUp(_ source: IconSource) -> NSImage? {
        let workspace = NSWorkspace.shared
        switch source {
        case let .app(bundleId):
            return workspace.urlForApplication(withBundleIdentifier: bundleId).map { workspace.icon(forFile: $0.path) }
        case let .file(path):
            return FileManager.default.fileExists(atPath: path) ? workspace.icon(forFile: path) : nil
        case let .url(url):
            return workspace.urlForApplication(toOpen: url).map { workspace.icon(forFile: $0.path) }
        case let .symbol(name):
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)
        case .menu:
            return AppGlyph.image(side: Layout.guideGlyphSize)
        }
    }
}
