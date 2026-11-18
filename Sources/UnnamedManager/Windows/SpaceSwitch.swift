import CoreGraphics
import Foundation
import UnnamedManagerKit

extension SpaceCommand: PerformableStep {
    func perform(in context: StepContext) async throws(PlanError) {
        try context.windows.switchSpace(direction)
    }
}

extension WindowControl {
    /// Switch Space (S-088, spec v17): on the focused window's display.
    /// With no focused window nothing happens, and that isn't a failure.
    func switchSpace(_ direction: SpaceDirection) throws(PlanError) {
        guard system.canControlWindows else {
            throw PlanError("Unnamed Manager needs Accessibility access to switch Spaces.")
        }
        guard let app = system.frontApp(), let window = system.focusedWindow(of: app), let frame = system.frame(of: window),
              let screen = WindowGeometry.screen(for: frame, among: system.screens()) else { return }
        system.switchSpace(direction, on: screen)
    }
}

extension AXWindowSystem {
    func switchSpace(_ direction: SpaceDirection, on screen: WindowGeometry.Screen) {
        DockSwipePoster.post(direction, at: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
    }
}

/// Posts the events of a fast trackpad swipe, which the Dock takes as a
/// switch with no slide (S-088). Each dock control event goes with an
/// almost empty gesture event, without which the Dock ignores it. The
/// events are undocumented (`DockSwipe`), so a macOS update can bring
/// the slide back or stop the switch, and nothing here can tell.
enum DockSwipePoster {
    /// `point` is on the display to switch, in top-left coordinates.
    static func post(_ direction: SpaceDirection, at point: CGPoint) {
        let payload = DockSwipe.needsPayload(osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        // Every event is built before any is posted, so a switch is never left half done.
        let events = DockSwipe.events(direction, payload: payload, time: mach_absolute_time()).compactMap {
            event($0, payload: payload, at: point)
        }
        guard events.count == 3 else {
            log.error("Switch Space: couldn't build the swipe")
            return
        }
        for event in events {
            guard let companion = CGEvent(source: nil) else { return }
            companion.setIntegerValueField(field(DockSwipe.typeField), value: DockSwipe.gestureType)
            event.post(tap: .cgSessionEventTap)
            companion.post(tap: .cgSessionEventTap)
        }
    }

    private static func event(_ swipe: DockSwipe.Event, payload: Bool, at point: CGPoint) -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        // No modifiers, since the leader's are often still held.
        event.flags = []
        event.location = point
        for (key, value) in swipe.integers { event.setIntegerValueField(field(key), value: value) }
        for (key, value) in swipe.doubles { event.setDoubleValueField(field(key), value: value) }
        guard payload else { return event }
        // macOS 27 checks a raw input payload, which only the event's serialized data can carry.
        let timestamp = event.timestamp != 0 ? event.timestamp : mach_absolute_time()
        guard let data = event.data as Data?,
              let bytes = DockSwipe.appending(DockSwipe.payload(for: swipe, timestamp: timestamp), to: Array(data)) else {
            return nil
        }
        return CGEvent(withDataAllocator: nil, data: Data(bytes) as CFData)
    }

    private static func field(_ raw: UInt32) -> CGEventField {
        // Swift takes any raw value for a C enum, private fields included.
        CGEventField(rawValue: raw)!
    }
}
