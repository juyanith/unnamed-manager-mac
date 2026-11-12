import Foundation

/// Open (S-010): a file, folder or URL in its default app.
public struct OpenAction: ActionValue {
    /// A path starting with / or ~, or a URL.
    public var target: String

    public init(target: String) {
        self.target = target
    }

    public static let kinds = [ActionKind(type: "open", displayName: "Open")]

    public var type: String { "open" }

    public static func blank(_ type: String) -> OpenAction {
        OpenAction(target: "")
    }

    public init(type: String, fields: ActionFields) throws {
        try fields.allow(["target"])
        target = try fields.required("target")
    }

    public func write(to fields: inout ActionFieldWriter) {
        fields.string("target", target)
    }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema(["target": ["type": "string"]], required: ["target"])
    }

    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        .open(try ActionPlanner.openURL(target, home: home))
    }

    /// The file's or folder's Finder icon, or the icon of the app that opens the URL (S-055).
    public func iconSource(home: URL) -> IconSource? {
        guard let url = try? ActionPlanner.openURL(target, home: home) else { return nil }
        // The path as written, ~ expanded: a folder's file URL adds a trailing slash.
        return url.isFileURL ? .file(ActionPlanner.expandTilde(target, home: home)) : .url(url)
    }
}
