import SwiftUI

/// Custom surfaces and states. System materials and semantic colors first:
/// these exist only where the system has nothing.
enum Surfaces {
    /// A keycap's fill in the Guide: a little translucent, so it picks up
    /// the glass behind it.
    static let keycap = Color.primary.opacity(0.08)
    /// A keycap's outline.
    static let keycapStroke = Color.primary.opacity(0.14)
    /// The one warning color: missing permission, config error, failed
    /// action. Always paired with a symbol or words, never color alone.
    static let warning = Color.orange
    /// A dimmed (unavailable) row in the Guide.
    static let unavailableOpacity = 0.45
}

/// The menu bar icon in each state (DESIGN.md, Archetype). Template symbols,
/// so they follow the menu bar's look.
enum StatusIcon {
    /// The app icon's two keycaps and ›, in one color (Icon/AppIcon.icon),
    /// drawn this many points square. Ready and capturing leaders.
    static let glyphSize: CGFloat = 17
    /// Enabled is off: the same glyph, drawn dimmed.
    static let offOpacity = 0.4
    /// A permission is missing, the config has an error, or Secure Event
    /// Input blocks keys. Shown as a badge on the ready symbol; this symbol
    /// is for places with room for a full icon.
    static let warning = "exclamationmark.triangle"
    /// The warning badge: a dot this wide in the icon's top trailing corner.
    static let badgeDiameter: CGFloat = 6
}
