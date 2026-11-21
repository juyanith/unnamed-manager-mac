import AppKit
import ApplicationServices
import MachO
import UnnamedManagerKit

/// Accessibility's private call for a window's id. Window tools all use it;
/// there's no public way from an AXUIElement to a CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

extension SpaceSendCommand: PerformableStep {
    func perform(in context: StepContext) async throws(PlanError) {
        try await context.windows.send(to: target, follow: follow)
    }
}

extension AXWindowSystem {
    func desktop(of window: WindowRef) -> DesktopPlace {
        guard let id = windowID(of: window), let sky = SkyLight.shared else { return .unknown }
        return sky.desktop(of: id)
    }

    /// The quiet way first: the window server's own move, which leaves the
    /// Space on screen as it is. When macOS refuses it, as 27.3 beta does
    /// for apps other than the Dock, carry the window by its title bar
    /// with the Mac's own Switch to Desktop shortcut (S-096). The quiet move
    /// leaves you on `from`, follow or not; `WindowControl` swipes after it.
    func send(_ window: WindowRef, toDesktop number: Int, from: Int, follow: Bool) async throws(PlanError) -> Int {
        guard let id = windowID(of: window), let sky = SkyLight.shared, let space = sky.desktop(number, besides: id) else {
            throw PlanError("Unable to find Space \(number).", alerts: true)
        }
        if sky.move(id, to: space), await sky.wait(until: id, isOn: space) { return from }
        log.info("Send to Space: the window server refused the move; carrying the window by its title bar")
        guard let frame = frame(of: window) else { throw PlanError("That window has closed.", alerts: true) }
        try await TitleBarCarry.carry(grabbing: frame, to: number)
        let moved = await sky.wait(until: id, isOn: space)
        if !follow { try? await TitleBarCarry.switchTo(desktop: from) }
        guard moved else {
            throw PlanError("macOS didn't move the window. Hold its title bar and press the shortcut for Space \(number).", alerts: true)
        }
        return follow ? number : from
    }
}

/// SkyLight, the window server's private framework (S-096). macOS has no
/// public way to put a window on another Space, so every call is looked up
/// when first needed; one that's missing means Send to Space can't.
final class SkyLight {
    static let shared = SkyLight()

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias PerformOperation = @convention(c) (UnsafeMutableRawPointer) -> Int64
    private typealias InitOperation = @convention(c) (AnyObject, Selector, NSArray, UInt64) -> AnyObject?

    private static let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    /// Every user Space and full-screen one, of the windows' own Spaces.
    private static let allSpaces: Int32 = 0x7
    private static let desktopType = 0

    private let connection: Int32
    private let copyDisplaySpaces: CopyDisplaySpaces
    private let copySpacesForWindows: CopySpacesForWindows

    private init?() {
        guard let handle = dlopen(Self.path, RTLD_NOW),
              let main = dlsym(handle, "SLSMainConnectionID"),
              let displays = dlsym(handle, "SLSCopyManagedDisplaySpaces"),
              let spaces = dlsym(handle, "SLSCopySpacesForWindows") else {
            log.error("Send to Space: SkyLight's Space calls are missing")
            return nil
        }
        connection = unsafeBitCast(main, to: MainConnection.self)()
        copyDisplaySpaces = unsafeBitCast(displays, to: CopyDisplaySpaces.self)
        copySpacesForWindows = unsafeBitCast(spaces, to: CopySpacesForWindows.self)
    }

    /// Each display's Spaces, in Mission Control's order, as (id, type).
    private func displays() -> [[(id: UInt64, type: Int)]] {
        let list = copyDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]] ?? []
        return list.map { display in
            (display["Spaces"] as? [[String: Any]] ?? []).compactMap { space in
                (space["ManagedSpaceID"] as? UInt64).map { ($0, space["type"] as? Int ?? Self.desktopType) }
            }
        }
    }

    /// The Spaces a window is on: one, or every one for a window on all of them.
    func spaces(of window: CGWindowID) -> [UInt64] {
        copySpacesForWindows(connection, Self.allSpaces, [NSNumber(value: window)] as CFArray)?.takeRetainedValue() as? [UInt64] ?? []
    }

    func desktop(of window: CGWindowID) -> DesktopPlace {
        let spaces = spaces(of: window)
        guard let space = spaces.first else { return .unknown }
        if spaces.count > 1 { return .everySpace }
        for display in displays() {
            guard let found = display.first(where: { $0.id == space }) else { continue }
            guard found.type == Self.desktopType else { return .fullScreen }
            let desktops = display.filter { $0.type == Self.desktopType }.map(\.id)
            return desktops.firstIndex(of: space).map { .desktop($0 + 1, of: desktops.count) } ?? .unknown
        }
        return .unknown
    }

    /// Desktop `number`, from 1, of the display the window's Space is on.
    func desktop(_ number: Int, besides window: CGWindowID) -> UInt64? {
        guard let space = spaces(of: window).first,
              let display = displays().first(where: { $0.contains { $0.id == space } }) else { return nil }
        let desktops = display.filter { $0.type == Self.desktopType }.map(\.id)
        return number <= desktops.count ? desktops[number - 1] : nil
    }

    /// Asks the window server to move the window, as macOS 26 and later do
    /// for their own window management. It answers at once, before the
    /// move, and says nothing when it refuses: `wait` tells.
    func move(_ window: CGWindowID, to space: UInt64) -> Bool {
        guard let perform = Self.performOperation,
              let type = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation") as? NSObject.Type else { return false }
        let selector = NSSelectorFromString("initWithWindows:spaceID:")
        // Swift can't call alloc, so it goes through perform. The operation is small and lives on in the window server's queue.
        guard type.instancesRespond(to: selector), let initialize = class_getMethodImplementation(type, selector),
              let allocated = type.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let operation = unsafeBitCast(initialize, to: InitOperation.self)(allocated, selector, [NSNumber(value: window)], space)
        else { return false }
        _ = perform(Unmanaged.passUnretained(operation).toOpaque())
        return true
    }

    /// True once the window is on the Space, checked for up to half a second.
    func wait(until window: CGWindowID, isOn space: UInt64) async -> Bool {
        for _ in 0..<10 {
            if spaces(of: window) == [space] { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return spaces(of: window) == [space]
    }

    /// The function that submits a bridged operation isn't exported, so
    /// it's found by name in SkyLight's symbol table, once.
    private static let performOperation: PerformOperation? = {
        let name = "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation"
        guard let address = localSymbol(name, inImageEndingWith: "/SkyLight") else {
            log.error("Send to Space: the bridged operation isn't in SkyLight")
            return nil
        }
        return unsafeBitCast(address, to: PerformOperation.self)
    }()

    private static func localSymbol(_ name: String, inImageEndingWith suffix: String) -> UnsafeRawPointer? {
        for index in 0..<_dyld_image_count() {
            guard let imageName = _dyld_get_image_name(index), String(cString: imageName).hasSuffix(suffix),
                  let header = _dyld_get_image_header(index) else { continue }
            let slide = _dyld_get_image_vmaddr_slide(index)
            var command = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
            var linkedit: segment_command_64?, symtab: symtab_command?
            for _ in 0..<header.pointee.ncmds {
                let load = command.load(as: load_command.self)
                if load.cmd == LC_SEGMENT_64 {
                    let segment = command.load(as: segment_command_64.self)
                    let segmentName = withUnsafeBytes(of: segment.segname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
                    if segmentName == "__LINKEDIT" { linkedit = segment }
                } else if load.cmd == LC_SYMTAB {
                    symtab = command.load(as: symtab_command.self)
                }
                command = command.advanced(by: Int(load.cmdsize))
            }
            guard let linkedit, let symtab else { return nil }
            let base = UInt(bitPattern: slide) &+ UInt(linkedit.vmaddr) &- UInt(linkedit.fileoff)
            guard let symbols = UnsafePointer<nlist_64>(bitPattern: base &+ UInt(symtab.symoff)),
                  let strings = UnsafePointer<CChar>(bitPattern: base &+ UInt(symtab.stroff)) else { return nil }
            for symbol in UnsafeBufferPointer(start: symbols, count: Int(symtab.nsyms)) where symbol.n_un.n_strx != 0 {
                if strcmp(strings + Int(symbol.n_un.n_strx), name) == 0 {
                    return UnsafeRawPointer(bitPattern: UInt(symbol.n_value) &+ UInt(bitPattern: slide))
                }
            }
            return nil
        }
        return nil
    }
}

/// The fallback for Send to Space (S-096): holds the window by its title
/// bar and presses the Mac's own Switch to Desktop shortcut, so the window
/// goes along, as when you do it by hand. It slides, and moves the pointer
/// for a moment.
enum TitleBarCarry {
    /// Holds the title bar, switches, lets go, and puts the pointer back.
    static func carry(grabbing frame: CGRect, to desktop: Int) async throws(PlanError) {
        let shortcut = try shortcut(for: desktop)
        await waitForModifiersUp()
        let source = CGEventSource(stateID: .privateState)
        let back = CGEvent(source: nil)?.location
        // The strip along the top is title bar or toolbar background in almost every window.
        let grab = CGPoint(x: frame.midX, y: frame.minY + 6)
        func mouse(_ type: CGEventType, at point: CGPoint) {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: SendShortcut.marker)
            event.post(tap: .cghidEventTap)
        }
        mouse(.mouseMoved, at: grab)
        mouse(.leftMouseDown, at: grab)
        try? await Task.sleep(for: .milliseconds(60))
        // A small drag, so macOS takes it as moving the window.
        mouse(.leftMouseDragged, at: CGPoint(x: grab.x + 2, y: grab.y))
        mouse(.leftMouseDragged, at: grab)
        try? await Task.sleep(for: .milliseconds(60))
        post(shortcut)
        // Long enough for the slide to the other Space.
        try? await Task.sleep(for: .milliseconds(700))
        mouse(.leftMouseUp, at: grab)
        if let back { CGWarpMouseCursorPosition(back) }
    }

    /// Goes to a desktop with its shortcut, sliding.
    static func switchTo(desktop: Int) async throws(PlanError) {
        let shortcut = try shortcut(for: desktop)
        await waitForModifiersUp()
        post(shortcut)
        try? await Task.sleep(for: .milliseconds(500))
    }

    /// The Mac's Switch to Desktop shortcuts are symbolic hot keys 118 to
    /// 133, for desktops 1 to 16: the character, the key code and the
    /// modifier flags, which use the same bits as CGEventFlags.
    private static func shortcut(for desktop: Int) throws(PlanError) -> (key: CGKeyCode, flags: CGEventFlags) {
        let hotKeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        guard (1...16).contains(desktop), let hotKey = hotKeys?[String(117 + desktop)] as? [String: Any],
              hotKey["enabled"] as? Bool == true,
              let parameters = (hotKey["value"] as? [String: Any])?["parameters"] as? [Int], parameters.count == 3 else {
            throw PlanError("Turn on “Switch to Desktop \(desktop)” in System Settings › Keyboard › Keyboard Shortcuts › Mission Control, so windows can go to Space \(desktop).", alerts: true)
        }
        return (CGKeyCode(parameters[1]), CGEventFlags(rawValue: UInt64(parameters[2])))
    }

    private static func post(_ shortcut: (key: CGKeyCode, flags: CGEventFlags)) {
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: shortcut.key, keyDown: down) else { return }
            event.flags = shortcut.flags
            event.setIntegerValueField(.eventSourceUserData, value: SendShortcut.marker)
            event.post(tap: .cghidEventTap)
        }
    }

    /// Waits up to a second for the leader's modifiers to be let go, since
    /// a click with Control held is a right click.
    private static func waitForModifiersUp() async {
        let held: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
        for _ in 0..<20 where !CGEventSource.flagsState(.hidSystemState).intersection(held).isEmpty {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
