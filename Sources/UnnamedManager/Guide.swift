import AppKit
import SwiftUI
import UnnamedManagerKit

/// What the Guide shows for one menu (S-005).
struct GuideContent: Equatable {
    struct Row: Equatable, Identifiable {
        var key: String
        var title: String
        var isMenu: Bool
        /// False for Context Aware with nothing to run in the app in front.
        var isAvailable = true
        /// "not available in Notes", shown on an unavailable row.
        var note: String?
        /// Where its icon comes from: an app, a file or a URL (S-054, S-055).
        var icon: IconSource?
        /// A held menu's first row, which has no key (S-091).
        var isCancel = false
        var id: String { isCancel ? "cancel" : key }
    }

    /// A group of rows: in Home, the entries on one set of modifiers under
    /// its name (S-050); elsewhere, one section with no title.
    struct Section: Equatable, Identifiable {
        var title: String?
        var rows: [Row]
        var id: String { title ?? "" }
    }

    var path: [String]
    var sections: [Section]
    /// True for Home, which puts a separator after its first group.
    var isHome = false
    var cancelKey: String
    /// nil when Back is turned off.
    var backKey: String?
    /// Why an action failed (S-015). When set, the Guide shows only this.
    var failure: String?
    /// In a held menu, the highlighted row: 0 is Cancel (S-091). nil in
    /// any other menu.
    var highlight: Int?
    /// What an empty list says in place of rows (S-092).
    var empty: String?

    /// A held menu when `highlight` is set: Cancel first, then the menu's rows.
    init(menu: BindingNode, path: [String], config: LoadedConfig, frontApp: String?, frontAppName: String? = nil,
         highlight: Int? = nil) {
        self.path = path
        self.highlight = highlight
        let appName = frontAppName ?? frontApp.flatMap(Self.appName) ?? "this app"
        var rows = menu.children.compactMap { child in
            child.path.lastStep.map { Self.row(child, key: $0.key, config: config, frontApp: frontApp, appName: appName) }
        }
        if highlight != nil {
            // In Recent Windows, Cancel is the window in front: choosing it changes nothing (spec v18).
            let front = menu.front
            rows.insert(Row(key: "", title: front?.title ?? "Cancel", isMenu: false,
                            icon: front?.app.map(IconSource.app), isCancel: true), at: 0)
        }
        if rows.isEmpty, menu.list != nil { empty = "No recent windows" }
        sections = [Section(rows: rows)]
        cancelKey = Self.footerLabel(config.cancelKey)
        backKey = config.backKey.map(Self.footerLabel)
    }

    /// Home: every leader and direct binding, by group, keys without modifiers.
    init(home: Home, path: [String], config: LoadedConfig, frontApp: String?, frontAppName: String? = nil) {
        self.path = path
        let appName = frontAppName ?? frontApp.flatMap(Self.appName) ?? "this app"
        sections = home.groups.map { group in
            Section(title: group.title, rows: group.entries.map {
                Self.row($0, key: $0.path.leader.key, config: config, frontApp: frontApp, appName: appName)
            })
        }
        isHome = true
        cancelKey = Self.footerLabel(config.cancelKey)
        backKey = config.backKey.map(Self.footerLabel)
    }

    private static func row(_ node: BindingNode, key: KeyName, config: LoadedConfig, frontApp: String?, appName: String) -> Row {
        let available = node.isMenu || config.isAvailable(node, frontApp: frontApp)
        let note = available ? node.item.flatMap { Self.note($0.marks) } : "not available in \(appName)"
        return Row(key: key.name, title: node.title, isMenu: node.isMenu,
                   isAvailable: available, note: note,
                   icon: config.iconSource(node))
    }

    /// How a list's item is marked (S-092): "minimized, on another display".
    static func note(_ marks: ListItem.Marks) -> String? {
        // Both places in one phrase, so the note fits the column.
        let place: (ListItem.Marks, String) = marks.isSuperset(of: [.otherSpace, .otherDisplay])
            ? ([.otherSpace, .otherDisplay], "on another Space and display")
            : marks.contains(.otherSpace) ? (.otherSpace, "on another Space") : (.otherDisplay, "on another display")
        let words: [(ListItem.Marks, String)] = [(.minimized, "minimized"), (.hidden, "hidden"), place]
        let note = words.filter { marks.contains($0.0) }.map(\.1).joined(separator: ", ")
        return note.isEmpty ? nil : note
    }

    /// Every row, in order.
    var rows: [Row] { sections.flatMap(\.rows) }

    /// The name people know an app by, from its bundle id.
    private static func appName(_ bundleId: String) -> String? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.localizedName
    }

    /// "esc" and "delete", as printed on a Mac keyboard, for the default
    /// keys; the key name otherwise.
    static func footerLabel(_ key: KeyName) -> String {
        switch key {
        case .escape: "esc"
        case .backspace: "delete"
        default: key.name
        }
    }

    /// Rows split into columns of at most 12, up to three (DESIGN.md). Home
    /// that doesn't fit one column puts its first group in a column of its
    /// own and packs the others after it, never splitting a group (S-050).
    var columns: [[Section]] {
        guard isHome else {
            let rows = rows
            let perColumn = max(Layout.guideRowsPerColumn,
                                Int((Double(rows.count) / Double(Layout.guideMaxColumns)).rounded(.up)))
            return stride(from: 0, to: rows.count, by: perColumn).map {
                [Section(rows: Array(rows[$0..<min($0 + perColumn, rows.count)]))]
            }
        }
        guard rows.count > Layout.guideRowsPerColumn, let first = sections.first else { return [sections] }
        var columns: [[Section]] = [[first]]
        var count = Layout.guideRowsPerColumn
        for section in sections.dropFirst() {
            if columns.count == 1 || count + section.rows.count > Layout.guideRowsPerColumn {
                columns.append([section])
                count = section.rows.count
            } else {
                columns[columns.count - 1].append(section)
                count += section.rows.count
            }
        }
        return columns
    }

    /// True when a column has an icon, so every row in it keeps the
    /// icon's space and the titles line up (S-054).
    static func showsIcons(_ column: [Section]) -> Bool {
        column.contains { $0.rows.contains { $0.icon != nil } }
    }

    /// Home side by side: a vertical divider after the first group's column.
    var dividesColumns: Bool { isHome && columns.count > 1 }

    /// True for the highlighted row of a held menu.
    func isHighlighted(_ row: Row) -> Bool {
        guard let highlight else { return false }
        return rows.firstIndex(of: row) == highlight
    }

    /// What VoiceOver says when the Guide opens or changes menu. A held
    /// menu says its highlighted row too: "Apps, Terminal, 1 of 4".
    var announcement: String {
        if let highlighted = highlightAnnouncement { return "\(path.last ?? ""), \(highlighted)" }
        if let empty { return "\(path.last ?? ""), \(empty)" }
        return "\(path.last ?? ""), \(rows.count) \(rows.count == 1 ? "key" : "keys")"
    }

    /// What VoiceOver says when only the highlight moves: "Browser, 2 of 4".
    /// Cancel isn't counted.
    var highlightAnnouncement: String? {
        guard let highlight, rows.indices.contains(highlight) else { return nil }
        let items = rows.count - 1
        guard highlight > 0 else { return rows[0].title == "Cancel" ? "Cancel" : "Cancel, \(rows[0].title)" }
        return "\(rows[highlight].title), \(highlight) of \(items)"
    }
}

/// The Guide: the path, the next keys, and how to cancel or go back.
struct GuideView: View {
    let content: GuideContent
    /// The error flash for an unbound key (S-018).
    var isFlashing = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            pathRow
            if let failure = content.failure {
                failureRow(failure)
            } else {
                if let empty = content.empty {
                    Text(empty).foregroundStyle(.secondary)
                } else {
                    menuRows
                }
                Divider()
                footer
            }
        }
        .backgroundPreferenceValue(HighlightBounds.self) { anchors in highlightFill(anchors) }
        .padding(Space.margin)
        .fixedSize()
        .background { background }
        .overlay {
            // The flash outlines the Guide in the accent, the Guide's one use of it.
            RoundedRectangle(cornerRadius: Radius.guide)
                .strokeBorder(Palette.accent, lineWidth: Space.xs / 2)
                .opacity(isFlashing ? 1 : 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(content.failure ?? content.announcement)
    }

    private func failureRow(_ message: String) -> some View {
        Label {
            Text(message)
                .frame(maxWidth: Layout.guideFailureWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(Surfaces.warning)
    }

    private var menuRows: some View {
        let columns = content.columns
        return HStack(alignment: .top, spacing: Space.xl) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                if index == 1 && content.dividesColumns { Divider() }
                // A Grid lines the titles up after the widest keycap.
                Grid(alignment: .leading, horizontalSpacing: Space.sm, verticalSpacing: Space.sm) {
                    ForEach(Array(column.enumerated()), id: \.element.id) { position, section in
                        // Home in one column: a separator after the current group.
                        let divided = content.isHome && columns.count == 1 && position == 1
                        if divided { Divider() }
                        if let title = section.title {
                            // A group right under another group's rows gets a step of air.
                            sectionHeader(title)
                                .padding(.top, position > 0 && !divided ? Space.xs : 0)
                        }
                        ForEach(section.rows) { row in rowView(row, icons: GuideContent.showsIcons(column)) }
                    }
                }
                .frame(width: Layout.guideColumnWidth, alignment: .leading)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private var pathRow: some View {
        Text(content.path.joined(separator: " › "))
            .font(.headline)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }

    private func rowView(_ row: GuideContent.Row, icons: Bool) -> some View {
        let highlighted = content.isHighlighted(row)
        // On the highlight, text is on the accent; elsewhere, Cancel is secondary.
        let primary: AnyShapeStyle = highlighted ? AnyShapeStyle(Palette.onAccent) : row.isCancel ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
        let secondary: AnyShapeStyle = highlighted ? AnyShapeStyle(Palette.onAccent) : AnyShapeStyle(.secondary)
        return GridRow {
            Group {
                if row.isCancel {
                    Image(systemName: "xmark")
                        .foregroundStyle(secondary)
                        .frame(minWidth: Layout.keycapMinWidth)
                } else {
                    Keycap(label: row.key)
                }
            }
            .gridColumnAlignment(.leading)
            .highlightBounds(highlighted)
            if icons { EntryIcon(source: row.icon) }
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(primary)
                if let note = row.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .highlightBounds(highlighted)
            Text("›")
                .foregroundStyle(secondary)
                .opacity(row.isMenu ? 1 : 0)
                .highlightBounds(highlighted)
        }
        .opacity(row.isAvailable ? 1 : Surfaces.unavailableOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.isCancel ? (row.title == "Cancel" ? "Cancel" : "Cancel, \(row.title)")
                            : "\(row.key), \(row.title)\(row.isMenu ? ", menu" : "")\(row.note.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    /// The highlight of a held menu: one fill behind its row's cells, a
    /// step of air around them, like a selected menu item (S-091). In one
    /// column it spans the Guide, which the footer can make wider than the
    /// column; in more, the cells already span their column.
    private func highlightFill(_ anchors: [Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            if let first = anchors.first {
                let cells = anchors.dropFirst().reduce(proxy[first]) { $0.union(proxy[$1]) }
                let row = content.columns.count == 1
                    ? CGRect(x: 0, y: cells.minY, width: proxy.size.width, height: cells.height) : cells
                let rect = row.insetBy(dx: -Space.sm, dy: -Space.xs)
                RoundedRectangle(cornerRadius: Radius.row)
                    .fill(Palette.accent)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)  // grid: ok measured from the row's cells, not a number
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Space.lg) {
            if content.highlight != nil { Text("Let go to choose") }
            footerKey(content.cancelKey, "Cancel")
            if let back = content.backKey { footerKey(back, "Back") }
        }
        // Centered under the rows, however many columns they take.
        .frame(maxWidth: .infinity)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func footerKey(_ key: String, _ title: String) -> some View {
        HStack(spacing: Space.xs) {
            Keycap(label: key, font: .system(.caption, design: .monospaced))
            Text(title)
        }
    }

    @ViewBuilder private var background: some View {
        // The Guide is all control layer, so rows sit on its glass (rule 9).
        if reduceTransparency {
            RoundedRectangle(cornerRadius: Radius.guide).fill(.regularMaterial)
        } else {
            Color.clear.glassEffect(.regular, in: .rect(cornerRadius: Radius.guide))
        }
    }
}

/// The frames of the highlighted row's cells, so the Grid can draw one
/// fill behind the whole row (S-091).
private struct HighlightBounds: PreferenceKey {
    static let defaultValue: [Anchor<CGRect>] = []
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value += nextValue()
    }
}

private extension View {
    /// Reports this cell's frame when its row is highlighted.
    func highlightBounds(_ on: Bool) -> some View {
        anchorPreference(key: HighlightBounds.self, value: .bounds) { on ? [$0] : [] }
    }
}

extension GuideContent {
    static let placeholder = GuideContent(path: [], rows: [], cancelKey: "esc", backKey: "delete")

    init(path: [String], rows: [Row], cancelKey: String, backKey: String?, failure: String? = nil) {
        self.path = path
        sections = [Section(rows: rows)]
        self.cancelKey = cancelKey
        self.backKey = backKey
        self.failure = failure
    }
}
