import SwiftUI

/// Corner radii. Nested corners are concentric: inner = outer - inset, so
/// a keycap (xs) inside the Guide (guide) with Space.margin padding lines up:
/// 26 - 20 = 6. Standard controls keep their own system radii.
enum Radius {
    /// Keycaps in the Guide and the key recorder, chips.
    static let xs: CGFloat = 6
    /// Custom controls.
    static let sm: CGFloat = 8
    /// Row hover and selection fills in custom lists.
    static let row: CGFloat = 10
    /// Cards, the error banner above the outline.
    static let md: CGFloat = 12
    /// The Guide and any other floating glass panel.
    static let guide: CGFloat = 26
}
