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
        var id: String { key }
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

    init(menu: BindingNode, path: [String], config: LoadedConfig, frontApp: String?, frontAppName: String? = nil) {
        self.path = path
        let appName = frontAppName ?? frontApp.flatMap(Self.appName) ?? "this app"
        let rows = menu.children.compactMap { child in
            child.path.lastStep.map { Self.row(child, key: $0.key, config: config, frontApp: frontApp, appName: appName) }
        }
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
        return Row(key: key.name, title: node.title, isMenu: node.isMenu,
                   isAvailable: available, note: available ? nil : "not available in \(appName)",
                   icon: config.iconSource(node))
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

    /// What VoiceOver says when the Guide opens or changes menu.
    var announcement: String {
        "\(path.last ?? ""), \(rows.count) \(rows.count == 1 ? "key" : "keys")"
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
                menuRows
                Divider()
                footer
            }
        }
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
        GridRow {
            Keycap(label: row.key)
                .gridColumnAlignment(.leading)
            if icons { EntryIcon(source: row.icon) }
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let note = row.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("›")
                .foregroundStyle(.secondary)
                .opacity(row.isMenu ? 1 : 0)
        }
        .opacity(row.isAvailable ? 1 : Surfaces.unavailableOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.key), \(row.title)\(row.isMenu ? ", menu" : "")\(row.note.map { ", \($0)" } ?? "")")
    }

    private var footer: some View {
        HStack(spacing: Space.lg) {
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
