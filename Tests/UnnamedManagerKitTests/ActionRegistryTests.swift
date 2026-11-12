import Foundation
import Testing
@testable import UnnamedManagerKit

/// What the compiler checked when every action type was an enum case, now
/// checked over the registry (S-060): every family gets every part.
@Suite("Action registry (S-060)")
struct ActionRegistryTests {
    static let kinds = ActionRegistry.standard.kinds

    /// Decodes one action with a registry, as the config reader does.
    static func decode(_ json: String, registry: ActionRegistry = .standard) throws -> Config.Action {
        let decoder = JSONDecoder()
        decoder.userInfo[ActionRegistry.userInfoKey] = registry
        return try decoder.decode(Config.Action.self, from: Data(json.utf8))
    }

    @Test("Every type is claimed by one family, and none is contextual")
    func uniqueTypes() {
        let types = Self.kinds.map(\.type)
        #expect(Set(types).count == types.count)
        #expect(!types.contains("contextual"))
    }

    @Test("Every kind has a UI name", arguments: kinds)
    func names(_ kind: ActionKind) {
        #expect(!kind.displayName.isEmpty)
    }

    @Test("A blank action of every kind writes and reads back the same", arguments: kinds)
    func roundTrip(_ kind: ActionKind) throws {
        let family = try #require(ActionRegistry.standard.family(for: kind.type))
        let action = Config.Action.family(AnyActionValue(family.blank(kind.type)))
        #expect(action.type == kind.type)
        #expect(try Self.decode(ConfigWriter.action(action, contexts: [])) == action)
    }

    @Test("The schema lists every kind, then Context Aware")
    func schema() {
        #expect(ConfigSchema.actionTypes == Self.kinds.map(\.type) + ["contextual"])
    }
}

extension ActionKind: CustomTestStringConvertible {
    public var testDescription: String { type }
}
