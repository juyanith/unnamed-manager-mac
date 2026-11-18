import Foundation

/// The events a fast horizontal trackpad swipe sends the Dock, which
/// switch Spaces without the slide (S-088). Adapted from joshuarli/iss
/// (ISC license). None of this is documented: the field numbers, the event
/// types and the raw input payload macOS 27 checks were found by reverse
/// engineering, so a macOS update can change them. The app turns each
/// event into a CGEvent and posts it with a companion gesture event.
public enum DockSwipe {
    /// The private field that holds an event's real type.
    public static let typeField: UInt32 = 55
    /// The event types: the companion gesture, and the dock control event with the swipe.
    public static let gestureType: Int64 = 29
    public static let dockControlType: Int64 = 30
    /// The field macOS 27 reads the raw input payload from.
    public static let payloadField: UInt16 = 4205

    enum Field {
        static let hidType: UInt32 = 110
        static let scrollY: UInt32 = 119
        static let swipeMask: UInt32 = 115
        static let motion: UInt32 = 123
        static let progress: UInt32 = 124
        static let positionX: UInt32 = 125
        static let positionY: UInt32 = 126
        static let velocityX: UInt32 = 129
        static let velocityY: UInt32 = 130
        static let phase: UInt32 = 132
        static let phaseAlias: UInt32 = 134
        static let flagBits: UInt32 = 135
        static let zoomDeltaY: UInt32 = 138
        static let zoomDeltaX: UInt32 = 139
        static let sourceTime: UInt32 = 169
    }

    static let dockSwipe: Int64 = 23
    static let horizontal: Int64 = 1

    public enum Phase: Int64, Sendable {
        case began = 1, changed = 2, ended = 4
    }

    /// One dock control event: the fields to set on a blank CGEvent.
    public struct Event: Equatable, Sendable {
        public let phase: Phase
        public internal(set) var integers: [UInt32: Int64] = [:]
        public internal(set) var doubles: [UInt32: Double] = [:]

        init(_ phase: Phase) {
            self.phase = phase
            integers[typeField] = dockControlType
            integers[Field.hidType] = dockSwipe
            integers[Field.phase] = phase.rawValue
            integers[Field.motion] = horizontal
        }
    }

    /// Whether this macOS checks the raw input payload: 27 and later.
    public static func needsPayload(osMajor: Int) -> Bool { osMajor >= 27 }

    /// Began, Changed and Ended for one switch. With `payload`, as macOS 27
    /// wants them; `time` is mach_absolute_time, which those carry.
    public static func events(_ direction: SpaceDirection, payload: Bool, time: UInt64 = 0) -> [Event] {
        let right = direction == .right
        return [Phase.began, .changed, .ended].map { phase in
            var event = Event(phase)
            if payload {
                event.doubles[Field.progress] = right ? -1 : 1
                event.integers[Field.phaseAlias] = phase.rawValue
                event.doubles[Field.zoomDeltaY] = 3
                event.doubles[Field.sourceTime] = Double(time)
                event.doubles[Field.positionX] = 0.1
                if phase == .ended { event.doubles[Field.velocityX] = right ? -9999 : 9999 }
            } else {
                // The smallest float there is, as bits, makes the switch instant.
                let tiny = right ? Float.leastNonzeroMagnitude : -Float.leastNonzeroMagnitude
                event.integers[Field.flagBits] = Int64(Int32(bitPattern: tiny.bitPattern))
                event.doubles[Field.scrollY] = 0
                event.doubles[Field.zoomDeltaX] = Double(Float.leastNonzeroMagnitude)
                if phase == .ended {
                    event.doubles[Field.velocityX] = right ? 400 : -400
                    event.doubles[Field.velocityY] = 0
                }
            }
            return event
        }
    }

    /// The raw input payload for one event: a queue element header, the
    /// fluid touch gesture, and its velocity when it has one. Little-endian.
    public static func payload(for event: Event, timestamp: UInt64) -> [UInt8] {
        let velocityX = event.doubles[Field.velocityX] ?? 0, velocityY = event.doubles[Field.velocityY] ?? 0
        let hasVelocity = velocityX != 0 || velocityY != 0 || event.phase == .ended
        var bytes: [UInt8] = []
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { bytes += $0 } }
        // Header: timestamp, sender, options, attribute length, event count.
        put(timestamp); put(UInt64(0)); put(UInt32(0)); put(UInt32(0)); put(UInt32(hasVelocity ? 2 : 1))
        // Fluid touch gesture: size, type 23, the phase in the options' top byte, depth, then its fields.
        put(UInt32(40)); put(UInt32(23)); put(UInt32(truncatingIfNeeded: (event.phase.rawValue & 0xFF) << 24)); put(UInt32(0))
        put(fixed(event.doubles[Field.positionX] ?? 0)); put(fixed(event.doubles[Field.positionY] ?? 0)); put(Int32(0))
        put(UInt32(truncatingIfNeeded: event.integers[Field.swipeMask] ?? 0))
        put(UInt16(truncatingIfNeeded: event.integers[Field.motion] ?? 0))
        put(UInt16(3))  // The Dock's primary gesture.
        put(fixed(event.doubles[Field.progress] ?? 0))
        if hasVelocity {
            // Velocity: size, type 9, options, depth 1, then x, y and z.
            put(UInt32(28)); put(UInt32(9)); put(UInt32(0)); put(UInt32(1))
            put(fixed(velocityX)); put(fixed(velocityY)); put(Int32(0))
        }
        return bytes
    }

    /// 16.16 fixed point; a value too small to show stays nonzero.
    static func fixed(_ value: Double) -> Int32 {
        let fixed = Int32(clamping: Int64(value * 65536))
        return fixed == 0 && value != 0 ? (value > 0 ? 1 : -1) : fixed
    }

    /// An event's serialized data with the payload added as field 4205, or
    /// nil when the data isn't in the format this knows (version 2).
    public static func appending(_ payload: [UInt8], to data: [UInt8]) -> [UInt8]? {
        guard data.count >= 4, data[0 ..< 4] == [0, 0, 0, 2], payload.count <= Int(UInt16.max) else { return nil }
        let length = UInt16(payload.count)
        return data + [UInt8(length >> 8), UInt8(length & 0xFF), UInt8(payloadField >> 8), UInt8(payloadField & 0xFF)] + payload
    }
}
