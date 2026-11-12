import Foundation

/// Home: the menu above the leaders, listing every leader and direct
/// binding in groups by their modifiers (SPEC.md, Home; S-050).
public struct Home: Sendable, Equatable {
    /// The top-level entries that share exactly these modifiers.
    public struct Group: Sendable, Equatable {
        public var modifiers: Modifiers
        /// In file order. Keys are unique, since chords are.
        public var entries: [BindingNode]

        /// "Hyper", "Meh", "Cmd", "Ctrl+Alt", or "No modifiers".
        public var title: String {
            modifiers.isEmpty ? "No modifiers" : modifiers.names.joined(separator: "+")
        }

        public func entry(for key: KeyName) -> BindingNode? {
            entries.first { $0.path.leader.key == key }
        }
    }

    /// The word for Home in the Guide's path (GLOSSARY.md).
    public static let title = "Home"

    /// The current group first, then the others in order of their first entry.
    public private(set) var groups: [Group]

    /// Groups `leaders`, putting the one with `current` modifiers first.
    public init(leaders: [BindingNode], current: Modifiers) {
        var groups: [Group] = []
        for leader in leaders {
            let modifiers = leader.path.leader.modifiers
            if let index = groups.firstIndex(where: { $0.modifiers == modifiers }) {
                groups[index].entries.append(leader)
            } else {
                groups.append(Group(modifiers: modifiers, entries: [leader]))
            }
        }
        if let index = groups.firstIndex(where: { $0.modifiers == current }) {
            groups.insert(groups.remove(at: index), at: 0)
        }
        self.groups = groups
    }

    /// The group of the leader you came from.
    public var current: Group? { groups.first }

    /// The entry a press picks, or nil when it's a key that isn't bound.
    /// In the current group the key alone picks, with some or all of its
    /// modifiers held. Any other entry needs its exact chord. A bare key
    /// prefers the current group over the group with no modifiers.
    public func entry(for chord: Chord) -> BindingNode? {
        let exact = groups.lazy.flatMap(\.entries).first { $0.path.leader == chord }
        var inCurrent: BindingNode?
        if let current, chord.modifiers.isSubset(of: current.modifiers) {
            inCurrent = current.entry(for: chord.key)
        }
        return chord.modifiers.isEmpty ? inCurrent ?? exact : exact ?? inCurrent
    }
}
