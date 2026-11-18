import Foundation

/// A key event from the event tap, reduced to what the engine needs.
public enum KeyEvent: Sendable, Equatable {
    case down(keyCode: UInt16, modifiers: Modifiers, isRepeat: Bool)
    case up(keyCode: UInt16)
    /// The modifiers held changed (flagsChanged).
    case flags(Modifiers)
}

/// What the app should do after one event.
public enum SequenceEffect: Sendable, Equatable {
    /// A sequence started or moved into a menu, including Back. Show it.
    /// `frontApp` is the app that was in front when the leader was pressed.
    case showMenu(BindingNode, path: [String], frontApp: String?)
    /// A held menu opened, or its highlight moved (spec v18). `highlight`
    /// is 0 for Cancel, and 1 for the menu's first child.
    case showHeld(BindingNode, highlight: Int, path: [String], frontApp: String?)
    /// Back from a leader's menu opened Home (S-050). Show it.
    case showHome(Home, path: [String], frontApp: String?)
    /// A binding was selected, or a direct binding's chord was pressed: run its
    /// action for `frontApp`. Any sequence has ended.
    case run(BindingNode, frontApp: String?)
    /// A Context Aware binding with nothing to run for the app in front.
    /// The sequence stays in its menu (S-013).
    case unavailable(BindingNode, path: [String])
    /// Cancel, or Back from a leader's menu. The sequence has ended.
    case cancelled
    /// A key that isn't bound. The sequence stays where it is.
    case unbound(path: [String])
}

public struct SequenceOutput: Sendable, Equatable {
    /// True when the event must not reach the app in front.
    public var consume: Bool
    public var effect: SequenceEffect?

    public static let pass = SequenceOutput(consume: false, effect: nil)
    static func consumed(_ effect: SequenceEffect? = nil) -> SequenceOutput { .init(consume: true, effect: effect) }
}

/// The sequence state machine (SPEC.md, During a sequence). Pure: key
/// events in, decisions out, no AppKit and no timers, so the event tap's
/// callback stays fast and every rule is unit-tested.
public struct SequenceEngine: Sendable {
    public private(set) var config: LoadedConfig
    /// The menus from the leader down to the current one. Empty when idle.
    public private(set) var stack: [BindingNode] = []
    /// Home, while the sequence is in it (S-050).
    public private(set) var home: Home?
    /// True once the sequence has been to Home, so its path starts there.
    private var viaHome = false
    /// Leader modifiers still physically held. They're ignored on step keys.
    private var heldLeaderModifiers: Modifiers = []
    /// Key-downs that were consumed, so their key-ups are consumed too.
    private var consumedKeys: Set<UInt16> = []
    /// The app in front right now, kept up to date by the app.
    private var frontApp: String?
    /// The app that was in front when the leader was pressed.
    public private(set) var sequenceFrontApp: String?
    /// The highlighted item while a held menu is held (spec v18): 0 is
    /// Cancel, 1 the first child. nil when the sequence isn't held.
    public private(set) var highlight: Int?
    /// The held leader's modifiers. Letting go of any of them chooses.
    private var holdModifiers: Modifiers = []

    public init(config: LoadedConfig) {
        self.config = config
    }

    public var isActive: Bool { !stack.isEmpty || home != nil }

    /// True while a held menu waits for its modifiers to be let go.
    public var isHeld: Bool { highlight != nil }

    /// The titles from the leader down: ["Commands", "Applications"], after
    /// "Home" once the sequence has been there.
    public var path: [String] { (viaHome ? [Home.title] : []) + stack.map(\.title) }

    /// Swaps in a new config. A running sequence ends.
    public mutating func replaceConfig(_ config: LoadedConfig) {
        self.config = config
        stack = []
        home = nil
        viaHome = false
        highlight = nil
    }

    /// The bundle id of the app in front. Call it whenever that changes.
    public mutating func setFrontApp(_ bundleId: String?) {
        frontApp = bundleId
    }

    /// Ends the sequence from outside (for example, Enabled turned off).
    public mutating func reset() {
        stack = []
        home = nil
        viaHome = false
        heldLeaderModifiers = []
        highlight = nil
    }

    public mutating func handle(_ event: KeyEvent) -> SequenceOutput {
        switch event {
        case let .flags(modifiers):
            // Once a leader modifier is released it stops being ignored.
            heldLeaderModifiers.formIntersection(modifiers)
            // Letting go of any held leader modifier chooses. The set is
            // compared, not the order, so a remapper's burst chooses the same.
            guard isHeld, !modifiers.isSuperset(of: holdModifiers) else { return .pass }
            return SequenceOutput(consume: false, effect: choose())

        case let .up(keyCode):
            return consumedKeys.remove(keyCode) != nil ? .consumed() : .pass

        case let .down(keyCode, modifiers, isRepeat):
            if !isActive {
                return idle(keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat)
            }
            consumedKeys.insert(keyCode)
            if isRepeat { return .consumed() }
            if let home { return pick(in: home, keyCode: keyCode, modifiers: modifiers) }
            return step(keyCode: keyCode, modifiers: modifiers)
        }
    }

    private mutating func idle(keyCode: UInt16, modifiers: Modifiers, isRepeat: Bool) -> SequenceOutput {
        guard let key = KeyName(keyCode: keyCode),
              let leader = config.leader(for: Chord(modifiers: modifiers, key: key)) else {
            // A repeat of a consumed leader is still consumed.
            return isRepeat && consumedKeys.contains(keyCode) ? .consumed() : .pass
        }
        if !leader.isMenu {
            // A direct binding runs at once, with no sequence. One that has
            // nothing to run for the app in front lets the chord through.
            guard config.isAvailable(leader, frontApp: frontApp) else { return .pass }
            if isRepeat { return .consumed() }
            consumedKeys.insert(keyCode)
            return .consumed(.run(leader, frontApp: frontApp))
        }
        if isRepeat { return .consumed() }
        consumedKeys.insert(keyCode)
        heldLeaderModifiers = modifiers
        sequenceFrontApp = frontApp
        stack = [leader]
        if leader.hold && !modifiers.isEmpty {
            holdModifiers = modifiers
            return .consumed(openHeld(leader))
        }
        return .consumed(.showMenu(leader, path: path, frontApp: sequenceFrontApp))
    }

    /// Puts the highlight on a held menu's first child, or on Cancel when
    /// it has none.
    private mutating func openHeld(_ menu: BindingNode) -> SequenceEffect {
        highlight = menu.children.isEmpty ? 0 : 1
        return .showHeld(menu, highlight: highlight!, path: path, frontApp: sequenceFrontApp)
    }

    /// Moves the highlight one item, wrapping through Cancel.
    private mutating func moveHighlight(in menu: BindingNode, by step: Int) -> SequenceEffect {
        let count = menu.children.count + 1
        highlight = ((highlight ?? 0) + step + count) % count
        return .showHeld(menu, highlight: highlight!, path: path, frontApp: sequenceFrontApp)
    }

    /// A key while held (SPEC.md, Held menus): the repeat key, with Shift,
    /// Down and Up move the highlight; a binding's key moves it there; a
    /// menu's key opens that menu, held.
    private mutating func stepHeld(_ menu: BindingNode, key: KeyName, extra: Modifiers) -> SequenceOutput {
        let reverse = extra == .shift && !holdModifiers.contains(.shift)
        if key == menu.repeatKey && (extra.isEmpty || reverse) {
            return .consumed(moveHighlight(in: menu, by: reverse ? -1 : 1))
        }
        guard extra.isEmpty else { return .consumed(.unbound(path: path)) }
        if let index = menu.children.firstIndex(where: { $0.path.lastStep?.key == key }) {
            let child = menu.children[index]
            if child.isMenu {
                stack.append(child)
                return .consumed(openHeld(child))
            }
            highlight = index + 1
            return .consumed(.showHeld(menu, highlight: index + 1, path: path, frontApp: sequenceFrontApp))
        }
        // An item on Down or Up wins over moving the highlight.
        if key == .down || key == .up {
            return .consumed(moveHighlight(in: menu, by: key == .down ? 1 : -1))
        }
        return .consumed(.unbound(path: path))
    }

    /// Letting go chose the highlighted item: a binding runs, a menu goes on
    /// as an ordinary menu, and Cancel ends the sequence.
    private mutating func choose() -> SequenceEffect? {
        guard let menu = stack.last, let index = highlight else { return nil }
        highlight = nil
        guard index > 0, index <= menu.children.count else {
            reset()
            return .cancelled
        }
        let child = menu.children[index - 1]
        if child.isMenu {
            stack.append(child)
            return .showMenu(child, path: path, frontApp: sequenceFrontApp)
        }
        guard config.isAvailable(child, frontApp: sequenceFrontApp) else {
            return .unavailable(child, path: path)
        }
        let app = sequenceFrontApp
        reset()
        return .run(child, frontApp: app)
    }

    private mutating func step(keyCode: UInt16, modifiers: Modifiers) -> SequenceOutput {
        guard let menu = stack.last else { return .pass }
        guard let key = KeyName(keyCode: keyCode) else { return .consumed(.unbound(path: path)) }
        let extra = modifiers.subtracting(heldLeaderModifiers)

        if extra.isEmpty && key == config.cancelKey {
            reset()
            return .consumed(.cancelled)
        }
        if extra.isEmpty && key == config.backKey {
            let leaving = stack.removeLast()
            guard let parent = stack.last else {
                // Above a leader's menu is Home, when there's more than the one entry.
                guard config.leaders.count > 1 else {
                    reset()
                    return .consumed(.cancelled)
                }
                let home = Home(leaders: config.leaders, current: leaving.path.leader.modifiers)
                self.home = home
                viaHome = true
                // Home isn't held.
                highlight = nil
                return .consumed(.showHome(home, path: path, frontApp: sequenceFrontApp))
            }
            if isHeld {
                // The highlight goes on the menu you came from.
                highlight = (parent.children.firstIndex(of: leaving) ?? 0) + 1
                return .consumed(.showHeld(parent, highlight: highlight!, path: path, frontApp: sequenceFrontApp))
            }
            return .consumed(.showMenu(parent, path: path, frontApp: sequenceFrontApp))
        }
        if isHeld { return stepHeld(menu, key: key, extra: extra) }
        guard extra.isEmpty, let child = menu.child(for: key) else {
            return .consumed(.unbound(path: path))
        }
        if child.isMenu {
            stack.append(child)
            return .consumed(.showMenu(child, path: path, frontApp: sequenceFrontApp))
        }
        guard config.isAvailable(child, frontApp: sequenceFrontApp) else {
            return .consumed(.unavailable(child, path: path))
        }
        let app = sequenceFrontApp
        reset()
        return .consumed(.run(child, frontApp: app))
    }

    /// A key in Home: Cancel and Back end the sequence, a leader opens its
    /// menu, and a direct binding runs (SPEC.md, Home).
    private mutating func pick(in home: Home, keyCode: UInt16, modifiers: Modifiers) -> SequenceOutput {
        guard let key = KeyName(keyCode: keyCode) else { return .consumed(.unbound(path: path)) }
        let extra = modifiers.subtracting(heldLeaderModifiers)
        if extra.isEmpty && (key == config.cancelKey || key == config.backKey) {
            reset()
            return .consumed(.cancelled)
        }
        guard let entry = home.entry(for: Chord(modifiers: modifiers, key: key)) else {
            return .consumed(.unbound(path: path))
        }
        if entry.isMenu {
            self.home = nil
            heldLeaderModifiers = modifiers
            stack = [entry]
            return .consumed(.showMenu(entry, path: path, frontApp: sequenceFrontApp))
        }
        guard config.isAvailable(entry, frontApp: sequenceFrontApp) else {
            return .consumed(.unavailable(entry, path: path))
        }
        let app = sequenceFrontApp
        reset()
        return .consumed(.run(entry, frontApp: app))
    }
}
