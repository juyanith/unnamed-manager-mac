import Foundation

/// The rule behind a config issue, by its id in the shared spec
/// (`spec/CONFIG-SPEC.md`, Validation), so the Mac and Windows apps are
/// checked against the same fixtures (S-059). Never shown in the UI.
public enum ConfigRule: String, Sendable, CaseIterable {
    // Errors
    case invalidJSON = "invalid-json"
    case version
    case unknownField = "unknown-field"
    case missingField = "missing-field"
    case wrongType = "wrong-type"
    case noEntries = "no-entries"
    case emptyTitle = "empty-title"
    case badKeys = "bad-keys"
    case duplicatePath = "duplicate-path"
    case noParent = "no-parent"
    case parentIsBinding = "parent-is-binding"
    case emptyMenu = "empty-menu"
    case stepModifiers = "step-modifiers"
    case stepIsRuntimeKey = "step-is-runtime-key"
    case badRuntimeKey = "bad-runtime-key"
    case sameCancelBack = "same-cancel-back"
    case negativeDelay = "negative-delay"
    case badUIValue = "bad-ui-value"
    case reservedChord = "reserved-chord"
    case undefinedAction = "undefined-action"
    case unknownActionType = "unknown-action-type"
    case badAppMode = "bad-app-mode"
    case undefinedContext = "undefined-context"
    case nestedContextual = "nested-contextual"
    case duplicateContext = "duplicate-context"
    // Warnings
    case unusedAction = "unused-action"
    case unusedContext = "unused-context"
    case keyNotOnPlatform = "key-not-on-platform"
}

/// Carried as a DecodingError's underlying error, so a decoding failure
/// keeps its message and still names its rule.
struct RuleMarker: Error {
    let rule: ConfigRule
}
