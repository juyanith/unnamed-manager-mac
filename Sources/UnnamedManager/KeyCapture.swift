import AppKit
import CoreGraphics
import Synchronization
import UnnamedManagerKit

/// The session-level event tap (SPEC.md, Permissions and lifecycle). It runs
/// on its own thread with its own run loop, so a busy main thread never
/// delays a keystroke anywhere on the Mac. `handler` is called on that
/// thread for every key event and decides at once whether to consume it.
final class KeyCapture {
    private let context: TapContext
    private var tap: CFMachPort?
    private var loop: TapLoop?

    /// `handler` runs on the tap thread. Return true to consume the event.
    init(handler: @escaping @Sendable (KeyEvent) -> Bool) {
        context = TapContext(handler: handler)
    }

    var isRunning: Bool { tap != nil }

    /// Installs the tap. Returns false when macOS refuses, which happens when
    /// a permission is missing or a new grant needs a relaunch.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: keyCaptureCallback,
                                          userInfo: Unmanaged.passUnretained(context).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            log.error("macOS refused the event tap")
            return false
        }
        context.setTap(tap)
        loop = TapLoop(source: source)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        log.info("Capturing leader keys")
        return true
    }

    /// Removes the tap, so no keys are captured.
    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        loop?.stop()
        CFMachPortInvalidate(tap)
        context.setTap(nil)
        self.tap = nil
        loop = nil
        log.info("Stopped capturing keys")
    }
}

/// What the C callback reaches through `userInfo`. Lives as long as the
/// KeyCapture that owns it.
nonisolated final class TapContext: Sendable {
    let handler: @Sendable (KeyEvent) -> Bool
    /// The tap, so the callback can turn it back on. Set on the main thread,
    /// read on the tap thread.
    private let tap = Mutex<UncheckedTap?>(nil)

    init(handler: @escaping @Sendable (KeyEvent) -> Bool) {
        self.handler = handler
    }

    func setTap(_ port: CFMachPort?) {
        tap.withLock { $0 = port.map(UncheckedTap.init) }
    }

    func handle(_ raw: RawKeyEvent) -> Bool {
        // Shortcuts the launcher sends itself (S-012) go straight through.
        if raw.isFromLauncher { return false }
        switch raw.type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turned the tap off (S-037). Turn it back on.
            log.notice("macOS turned off the event tap (\(raw.type.rawValue)); turning it back on")
            if let port = tap.withLock({ $0?.port }) { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        case .keyDown:
            return handler(.down(keyCode: raw.keyCode, modifiers: Modifiers(raw.flags), isRepeat: raw.isRepeat))
        case .keyUp:
            return handler(.up(keyCode: raw.keyCode))
        case .flagsChanged:
            return handler(.flags(Modifiers(raw.flags)))
        default:
            return false
        }
    }
}

/// CFMachPort isn't marked Sendable. CGEvent allows enabling a tap from
/// any thread.
nonisolated struct UncheckedTap: @unchecked Sendable {
    let port: CFMachPort
}

/// A thread that runs the tap's run loop source until stopped.
nonisolated final class TapLoop: Sendable {
    private let runLoop: UncheckedRunLoop

    init(source: CFRunLoopSource) {
        let start = LoopStart(source: source)
        let thread = Thread {
            let loop = CFRunLoopGetCurrent()!
            CFRunLoopAddSource(loop, start.source.source, .commonModes)
            start.loop.withLock { $0 = UncheckedRunLoop(loop: loop) }
            start.ready.signal()
            CFRunLoopRun()
        }
        thread.name = "net.unnamed.manager.event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        start.ready.wait()
        runLoop = start.loop.withLock { $0! }
    }

    func stop() {
        CFRunLoopStop(runLoop.loop)
    }

    private final class LoopStart: Sendable {
        let source: UncheckedSource
        let loop = Mutex<UncheckedRunLoop?>(nil)
        let ready = DispatchSemaphore(value: 0)
        init(source: CFRunLoopSource) { self.source = UncheckedSource(source: source) }
    }
}

/// CF run loop types aren't marked Sendable. A run loop may be stopped
/// from any thread, and the source is only added on the tap thread.
nonisolated struct UncheckedRunLoop: @unchecked Sendable { let loop: CFRunLoop }
nonisolated struct UncheckedSource: @unchecked Sendable { let source: CFRunLoopSource }

/// The parts of a CGEvent the tap needs, as plain values.
nonisolated struct RawKeyEvent: Sendable {
    var type: CGEventType
    var keyCode: UInt16
    var isRepeat: Bool
    var flags: CGEventFlags
    /// Posted by Send Shortcut, marked with SendShortcut.marker.
    var isFromLauncher: Bool
}

/// The C callback. It runs on the tap thread.
nonisolated private func keyCaptureCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                            userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<TapContext>.fromOpaque(userInfo).takeUnretainedValue()
    let raw = RawKeyEvent(type: type,
                          keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
                          isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                          flags: event.flags,
                          isFromLauncher: event.getIntegerValueField(.eventSourceUserData) == SendShortcut.marker)
    return context.handle(raw) ? nil : Unmanaged.passUnretained(event)
}

extension Modifiers {
    /// The four chord modifiers in a CGEvent's flags. Caps Lock and Fn are ignored.
    nonisolated init(_ flags: CGEventFlags) {
        var modifiers: Modifiers = []
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        self = modifiers
    }
}

/// The sequence engine behind a lock, so the tap thread can run it while
/// the main thread swaps in a new config.
nonisolated final class EngineBox: Sendable {
    private let engine = Mutex<SequenceEngine?>(nil)
    /// While a key is being recorded in the Bindings window, every key
    /// passes through, so the recorder sees the leader too.
    private let paused = Mutex(false)

    func setPaused(_ value: Bool) {
        paused.withLock { $0 = value }
        if value { reset() }
    }

    /// Called on the tap thread for every event.
    func handle(_ event: KeyEvent) -> SequenceOutput {
        if paused.withLock({ $0 }) { return .pass }
        return engine.withLock { engine in
            guard var current = engine else { return .pass }
            let output = current.handle(event)
            engine = current
            return output
        }
    }

    func replace(_ config: LoadedConfig) {
        engine.withLock { engine in
            if engine == nil {
                engine = SequenceEngine(config: config)
                engine?.setFrontApp(frontApp)
            } else {
                engine?.replaceConfig(config)
            }
        }
    }

    func reset() {
        engine.withLock { $0?.reset() }
    }

    /// The app in front, for Context Aware (S-013).
    func setFrontApp(_ bundleId: String?) {
        engine.withLock { engine in
            frontApp = bundleId
            engine?.setFrontApp(bundleId)
        }
    }

    /// Kept so a config that loads later starts with the right app.
    private nonisolated(unsafe) var frontApp: String?
}
