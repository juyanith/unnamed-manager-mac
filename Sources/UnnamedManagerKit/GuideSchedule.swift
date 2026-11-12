import Foundation

/// What the app should do with the Guide and the sound.
public enum GuideCommand: Sendable, Equatable {
    /// Show this menu, or update the Guide to it if it's already up.
    case show(BindingNode, path: [String], frontApp: String?)
    /// Show Home, or update the Guide to it (S-050).
    case showHome(Home, path: [String], frontApp: String?)
    case hide
    /// Flash the Guide for an unbound or unavailable key (S-018).
    case flash
    /// Play the system alert sound (S-018).
    case bell
    /// The timeout ran out: end the engine's sequence (S-017).
    case endSequence
}

/// When the Guide shows, updates and hides (SPEC.md, HUD). Pure: engine
/// effects and timer fires in, with the time in milliseconds; commands
/// out. The app arms one timer for `nextDeadline` and calls `tick`.
public struct GuideSchedule: Sendable, Equatable {
    public var delayMs: Double
    public var timeoutMs: Double
    public var showHud: Bool
    public var errorFlash: Bool
    public var errorBell: Bool

    /// True while the Guide is on screen.
    public private(set) var isVisible = false
    /// The menu to show once the delay passes, while the Guide isn't up yet.
    private var pending: GuideCommand?
    /// When the pending menu shows.
    private var showAt: Double?
    /// When the visible Guide times out.
    private var timeoutAt: Double?

    public init(runtime: Config.Runtime, ui: Config.UI) {
        delayMs = Double(runtime.hudDelayMs)
        timeoutMs = Double(runtime.timeoutMs)
        showHud = runtime.showHud
        errorFlash = ui.errorFlash
        errorBell = ui.errorBell
    }

    /// The next time `tick` has something to do, if any.
    public var nextDeadline: Double? {
        [showAt, timeoutAt].compactMap { $0 }.min()
    }

    public mutating func handle(_ effect: SequenceEffect, at now: Double) -> [GuideCommand] {
        switch effect {
        case let .showMenu(menu, path, frontApp):
            return show(.show(menu, path: path, frontApp: frontApp), at: now)

        case let .showHome(home, path, frontApp):
            return show(.showHome(home, path: path, frontApp: frontApp), at: now)

        case .run, .cancelled:
            let wasVisible = isVisible
            clear()
            return wasVisible ? [.hide] : []

        case .unbound, .unavailable:
            var commands: [GuideCommand] = errorBell ? [.bell] : []
            guard showHud else { return commands }
            if isVisible {
                restartTimeout(at: now)
            } else {
                // A wrong key suggests the sequence was forgotten: show at once.
                commands += reveal(at: now)
            }
            if errorFlash { commands.append(.flash) }
            return commands
        }
    }

    public mutating func tick(at now: Double) -> [GuideCommand] {
        if let showAt, now >= showAt {
            return reveal(at: now)
        }
        if let timeoutAt, now >= timeoutAt {
            clear()
            return [.hide, .endSequence]
        }
        return []
    }

    /// Shows a menu or Home now, or once the delay passes.
    private mutating func show(_ show: GuideCommand, at now: Double) -> [GuideCommand] {
        guard showHud else { return [] }
        if isVisible {
            restartTimeout(at: now)
            return [show]
        }
        pending = show
        if delayMs <= 0 { return reveal(at: now) }
        // Every key, Back included, restarts the delay.
        showAt = now + delayMs
        return []
    }

    /// Shows the pending menu now and starts the timeout.
    private mutating func reveal(at now: Double) -> [GuideCommand] {
        guard let pending else { return [] }
        self.pending = nil
        showAt = nil
        isVisible = true
        restartTimeout(at: now)
        return [pending]
    }

    /// The timeout runs only while the Guide is visible, from the last key.
    private mutating func restartTimeout(at now: Double) {
        timeoutAt = timeoutMs > 0 && isVisible ? now + timeoutMs : nil
    }

    private mutating func clear() {
        isVisible = false
        pending = nil
        showAt = nil
        timeoutAt = nil
    }
}
