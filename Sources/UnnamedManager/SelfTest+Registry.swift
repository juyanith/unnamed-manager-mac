import Foundation
import UnnamedManagerKit

/// A family only the self-test knows, with a step the app runs itself, so
/// the check proves a new kind of action needs no change to a shared file (S-060).
nonisolated private struct ChimeAction: ActionValue {
    static let kinds = [ActionKind(type: "selftest.chime", displayName: "Chime")]
    var type: String { "selftest.chime" }
    static func blank(_ type: String) -> ChimeAction { ChimeAction() }
    init() {}
    init(type: String, fields: ActionFields) throws { try fields.allow([]) }
    func write(to fields: inout ActionFieldWriter) {}
    static func schema(_ type: String) -> ActionSchema { ActionSchema() }
    func plan(home: URL) throws(PlanError) -> ActionPlan { .custom(AnyActionStep(ChimeStep())) }
}

nonisolated private struct ChimeStep: PerformableStep {
    nonisolated(unsafe) static var rung = 0
    func perform() async throws(PlanError) { Self.rung += 1 }
}

/// A step with no performer in the app, which must fail with a message.
nonisolated private struct SilentStep: ActionStep {}

extension SelfTest {
    static func registryChecks() async {
        let registry = ActionRegistry.standard.adding(ChimeAction.self)
        let json = #"{ "version": 1, "entries": [ { "keys": "Cmd+Opt+C", "title": "Chime", "action": "chime" } ], "actions": { "chime": { "type": "selftest.chime" } } }"#
        guard case let .success(loaded) = ConfigLoader.load(Data(json.utf8), registry: registry),
              let action = loaded.config.actions["chime"] else {
            check("S-060 a family added outside the app loads", false, "didn't load")
            return
        }
        check("S-060 a family added outside the app loads", action.displayName == "Chime")

        let recorder = RecordingPerformer()
        try? await ActionRunner(performer: recorder).run(action, id: "chime")
        check("S-060 its step reaches the performer unchanged",
              recorder.plans == [.custom(AnyActionStep(ChimeStep()))], "\(recorder.plans)")

        let before = ChimeStep.rung
        try? await ActionRunner().run(action, id: "chime")
        check("S-060 the app runs a family's own step", ChimeStep.rung == before + 1)

        do throws(PlanError) {
            try await SystemPerformer().perform(.custom(AnyActionStep(SilentStep())))
            check("S-060 a step the app can't run says so", false, "no failure")
        } catch {
            check("S-060 a step the app can't run says so", error.message == "This kind of action can't run on this Mac yet.", error.message)
        }
    }
}
