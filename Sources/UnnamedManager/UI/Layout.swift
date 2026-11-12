import AppKit
import SwiftUI

/// Fixed sizes. Spacing lives in Space (Grid.swift).
enum Layout {
    /// The Settings window's single Form.
    static let settingsWidth: CGFloat = 520
    /// Settings grows to this height before it scrolls, so all five sections
    /// fit, unless the screen is shorter: then it stops 80 points short of it.
    static var settingsMaxHeight: CGFloat {
        min(960, (NSScreen.main?.visibleFrame.height ?? 920) - 80)
    }
    /// The first-run welcome window.
    static let welcomeWidth: CGFloat = 520
    /// Bindings window sidebar.
    static let sidebarMin: CGFloat = 180
    static let sidebarIdeal: CGFloat = 200
    /// Bindings window minimum and first-open size.
    static let windowMin = CGSize(width: 900, height: 480)
    static let windowDefault = CGSize(width: 1180, height: 680)

    /// The Bindings window's editor pane beside the outline.
    static let editorPaneWidth: CGFloat = 280
    /// The outline's Key column, and the key recorder.
    static let keyColumnWidth: CGFloat = 112
    static let keyRecorderWidth: CGFloat = 160
    /// The outline's Action column.
    static let actionColumnWidth: CGFloat = 148
    /// The Actions and Contexts pages' list beside the form.
    static let listPaneWidth: CGFloat = 280
    /// The Help page's form, so its lines stay readable in a wide window.
    static let helpMaxWidth: CGFloat = 640

    /// The Guide: rows per column before it adds a column (12, then 24).
    static let guideRowsPerColumn = 12
    static let guideMaxColumns = 3
    /// Width of one Guide column; titles longer than this truncate.
    static let guideColumnWidth: CGFloat = 240
    /// An app's icon in a Guide row (S-054).
    static let guideIconSize: CGFloat = 24
    /// The app's glyph on a menu row, about the size of a large symbol.
    static let guideGlyphSize: CGFloat = 16
    /// The widest a failure message gets before it wraps (S-015).
    static let guideFailureWidth: CGFloat = 360
    /// A keycap's minimum width, so "E" and "F12" line up in a column.
    static let keycapMinWidth: CGFloat = 28
}
