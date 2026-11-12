import SwiftUI

/// Every animation in the app. Feeling: quick and out of the way
/// (DESIGN.md), so motion is short fades and nothing travels.
/// Each token returns nil under Reduce Motion: pass the environment value.
///   @Environment(\.accessibilityReduceMotion) private var reduceMotion
///   withAnimation(Motion.guideAppear(reduceMotion)) { ... }
enum Motion {
    /// The Guide fading in after its delay.
    static func guideAppear(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }

    /// The Guide fading out when the sequence ends.
    static func guideDismiss(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeIn(duration: 0.12)
    }

    /// The error flash on an unbound key: in, then back out.
    static func errorFlash(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }

    /// How long the error flash stays before it fades back.
    static let errorFlashHold: Duration = .milliseconds(180)

    /// Hover fills on custom rows and buttons in the Bindings window.
    static func hover(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.1)
    }

    /// Rows added, moved or removed in the outline.
    static func listChange(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.2)
    }

    /// The Guide's fade, for the AppKit panel (NSAnimationContext). Same
    /// length as guideAppear and guideDismiss. Skipped under Reduce Motion.
    static let guideFadeSeconds: TimeInterval = 0.12

    /// How long a failed action's message stays in the Guide (S-015).
    static let errorMessageHold: Duration = .seconds(2)
}
