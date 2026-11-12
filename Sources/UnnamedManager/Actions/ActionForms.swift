import SwiftUI
import UnnamedManagerKit

/// A family's form on the Actions page (S-060). A family conforms in its
/// own app file, so a new family changes no shared view.
protocol EditableAction: ActionValue {
    associatedtype Form: View
    @ViewBuilder static func form(_ value: Binding<Self>) -> Form
}

extension EditableAction {
    /// The form, editing the action in place.
    static func form(editing action: Binding<Config.Action>, current: Self) -> AnyView {
        AnyView(form(Binding(get: { (action.wrappedValue.familyValue as? Self) ?? current },
                             set: { action.wrappedValue = .family(AnyActionValue($0)) })))
    }
}

/// The form for whichever family the action belongs to.
struct FamilyForm: View {
    @Binding var action: Config.Action
    let value: any ActionValue

    var body: some View {
        if let editable = value as? any EditableAction {
            form(for: editable)
        } else {
            Section {
                Text("This action has no settings here. Edit it in the config file.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func form<E: EditableAction>(for value: E) -> AnyView {
        E.form(editing: $action, current: value)
    }
}

extension BasicAction: EditableAction {
    static func form(_ value: Binding<BasicAction>) -> some View {
        Section {
            switch value.wrappedValue {
            case .noop:
                Text("This action does nothing. Use it to reserve a key.")
                    .foregroundStyle(.secondary)
            case .help:
                Text("Opens the Help page of the Bindings window, which lists your leaders and direct bindings.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
