import CoreGraphics
import UnnamedManagerKit

/// Presses chords in the app in front (S-012). Each event carries only its
/// chord's own modifiers, never the leader's that may still be held, and a
/// marker so the launcher's own event tap lets it through untouched.
enum SendShortcut {
    /// Set in `eventSourceUserData` on every event the launcher posts.
    nonisolated static let marker: Int64 = 0x554C_4E43  // "ULNC"

    /// Key-down and key-up events for each chord, in order.
    static func events(for chords: [Chord]) throws(PlanError) -> [CGEvent] {
        // A private source, so the physical modifier state isn't mixed in.
        let source = CGEventSource(stateID: .privateState)
        var events: [CGEvent] = []
        for chord in chords {
            guard let code = chord.key.keyCode else {
                throw PlanError("Send Shortcut can't press \(chord.key.name): a Mac keyboard doesn't have it.")
            }
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown) else {
                    throw PlanError("Send Shortcut couldn't make the key event for \(chord).")
                }
                event.flags = CGEventFlags(chord.modifiers)
                event.setIntegerValueField(.eventSourceUserData, value: marker)
                events.append(event)
            }
        }
        return events
    }

    /// Posts the events to the HID level, so they go to the app in front.
    static func post(_ chords: [Chord]) throws(PlanError) {
        for event in try events(for: chords) {
            event.post(tap: .cghidEventTap)
        }
    }
}

extension CGEventFlags {
    /// Exactly these chord modifiers, nothing else.
    init(_ modifiers: Modifiers) {
        var flags: CGEventFlags = []
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        self = flags
    }
}
