import AppKit
import SwiftUI
import UnnamedManagerKit

/// What the menu bar menu and icon show, worked out from the app's state,
/// so the self-test can check it without opening the menu (S-002, S-008, S-009).
struct MenuBarStatus: Equatable {
    enum Icon: Equatable { case ready, off, warning }

    var icon: Icon
    /// The disabled first line when the launcher is off, or nil.
    var statusLine: String?
    /// The disabled line under the version: when the config last loaded.
    var configLine: String?
    var missingPermissions: [Permission]
    var needsRelaunch: Bool
    /// Secure Event Input is on, so leaders can't be seen (S-038).
    var keyboardIsSecured: Bool
    /// The app this one grew out of is running too and may take the same keys (S-058).
    var otherAppRunning: Bool
    /// The first config error, and how many more there are.
    var firstError: String?
    var moreErrors: Int

    init(launcher: Launcher, store: ConfigStore, otherAppRunning: Bool = false, now: Date = .now) {
        self.otherAppRunning = otherAppRunning
        missingPermissions = launcher.missingPermissions
        needsRelaunch = launcher.needsRelaunch
        keyboardIsSecured = launcher.secureInputIsOn && launcher.isEnabled
        firstError = store.errors.first?.message
        moreErrors = max(0, store.errors.count - 1)
        let attention = !missingPermissions.isEmpty || needsRelaunch || firstError != nil || keyboardIsSecured || otherAppRunning
        icon = !launcher.isEnabled ? .off : attention ? .warning : .ready
        statusLine = launcher.isEnabled ? nil : "Not capturing leaders"
        if store.createdStarter, firstError == nil {
            configLine = "Created config file"
        } else if let loadedAt = store.loadedAt {
            configLine = "Config loaded at \(loadedAt.formatted(date: .omitted, time: .shortened))"
        } else {
            configLine = nil
        }
    }

    /// The status item's VoiceOver label, which carries the state.
    var accessibilityLabel: String {
        switch icon {
        case .ready: "Unnamed Manager"
        case .off: "Unnamed Manager, off"
        case .warning: !missingPermissions.isEmpty ? "Unnamed Manager, needs permission"
            : keyboardIsSecured ? "Unnamed Manager, keyboard is secured" : "Unnamed Manager, needs attention"
        }
    }
}

/// The version line in the menu bar menu (S-051): "Version 0.1.3" for a
/// release, and the branch and commit too for a local build, which
/// `build.sh` records in Info.plist when APP_VERSION isn't set.
enum AppVersion {
    static var line: String {
        line(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
             source: Bundle.main.object(forInfoDictionaryKey: "UNBuildSource") as? String)
    }

    static func line(version: String?, source: String?) -> String {
        let base = "Version \(version ?? "unknown")"
        guard let source, !source.isEmpty else { return base }
        return "\(base) (\(source))"
    }
}

/// The menu bar menu. It acts as the app's menu bar while no window is open
/// (DESIGN.md, Command map).
struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var launcher = model.launcher
        let status = MenuBarStatus(launcher: launcher, store: model.store, otherAppRunning: model.migration.isLauncherRunning)

        if let line = status.statusLine {
            Text(line)
        }
        if !status.missingPermissions.isEmpty {
            Section("Needs Permission") {
                ForEach(status.missingPermissions) { permission in
                    Button("\(permission.rawValue) — Open Settings…") { permission.openSettings() }
                }
                Text("Unnamed Manager needs both to capture your leader keys.")
            }
        }
        if status.keyboardIsSecured {
            Section("Keyboard Is Secured by Another App") {
                Text("A password field or another app has turned on Secure Input, so leader keys can't be seen until it's turned off.")
            }
        }
        LauncherRunningSection()
        if status.needsRelaunch {
            Button("Relaunch to Finish Setup") { launcher.relaunch() }
        }
        if let error = status.firstError {
            Section("Config Error") {
                Text(error)
                if status.moreErrors > 0 { Text("+\(status.moreErrors) more") }
                Button("Open Config File") { model.store.openFile() }
            }
        }
        Divider()
        Toggle("Enabled", isOn: $launcher.isEnabled)
        Divider()
        Button("Reload Config") { model.store.reload() }
            .keyboardShortcut("r")
        Button("Open Config File") { model.store.openFile() }
        Button("Show Config in Finder") { model.store.showInFinder() }
        Divider()
        Button("Edit Bindings…") {
            openWindow(id: WindowID.bindings)
            NSApp.activate()
        }
        .keyboardShortcut("b")
        Button("Settings…") {
            openSettings()
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Button("Help") { model.showHelp() }
        Divider()
        Text(AppVersion.line)
        if let line = status.configLine {
            Text(line)
        }
        Button("Quit Unnamed Manager") {
            launcher.stop()
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// The menu bar icon in its three states (DESIGN-SYSTEM.md, StatusIcon).
struct MenuBarIcon: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let status = MenuBarStatus(launcher: model.launcher, store: model.store, otherAppRunning: model.migration.isLauncherRunning)
        Image(nsImage: Self.image(for: status.icon))
            .accessibilityLabel(status.accessibilityLabel)
            .task { model.openBindingsWindow = { [openWindow] in openWindow(id: WindowID.bindings) } }
    }

    /// A template image: dimmed when off, with a badge when something needs attention.
    static func image(for icon: MenuBarStatus.Icon) -> NSImage {
        let side = StatusIcon.glyphSize
        // Room on the right for the warning badge, so it covers less of the glyph.
        let image = NSImage(size: NSSize(width: side + StatusIcon.badgeDiameter / 2, height: side), flipped: true) { rect in
            AppGlyph.draw(in: NSRect(x: 0, y: 0, width: side, height: side), alpha: icon == .off ? StatusIcon.offOpacity : 1)
            if icon == .warning {
                // A filled dot in the top trailing corner, punched out of the symbol.
                let d = StatusIcon.badgeDiameter
                let dot = NSRect(x: rect.maxX - d, y: rect.minY, width: d, height: d)
                NSColor.clear.set()
                NSBezierPath(ovalIn: dot.insetBy(dx: -2, dy: -2)).fill(using: .copy)
                NSColor.black.set()
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

extension MenuBarIcon {
    /// The three states side by side on a light and a dark menu bar, as a
    /// PNG, for snapshots (S-041). Template images take the bar's color.
    static func contactSheet() -> Data? {
        let states: [MenuBarStatus.Icon] = [.ready, .off, .warning]
        let cell = NSSize(width: 44, height: 28)
        let scale: CGFloat = 4
        let size = NSSize(width: cell.width * CGFloat(states.count), height: cell.height * 2)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for (row, dark) in [false, true].enumerated() {
            let y = size.height - cell.height * CGFloat(row + 1)
            (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
            NSRect(x: 0, y: y, width: size.width, height: cell.height).fill()
            for (column, state) in states.enumerated() {
                let icon = image(for: state)
                let tinted = NSImage(size: icon.size, flipped: false) { rect in
                    icon.draw(in: rect)
                    (dark ? NSColor.white : NSColor.black).set()
                    rect.fill(using: .sourceAtop)
                    return true
                }
                let origin = NSPoint(x: CGFloat(column) * cell.width + (cell.width - icon.size.width) / 2,
                                     y: y + (cell.height - icon.size.height) / 2)
                tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

