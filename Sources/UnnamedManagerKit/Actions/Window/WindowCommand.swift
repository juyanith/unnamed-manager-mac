import CoreGraphics

/// What a window action does to the focused window of the app in front
/// (spec v2). The window families plan one, and the app carries it out.
public enum WindowCommand: ActionStep {
    case maximize(toggle: Bool)

    /// The verb in "<App> has no window to maximize."
    public var verb: String {
        switch self {
        case .maximize: "maximize"
        }
    }
}
