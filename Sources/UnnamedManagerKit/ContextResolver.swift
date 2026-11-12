import Foundation

/// Picks the action Context Aware runs for the app in front (SPEC.md,
/// Actions, contextual).
public enum ContextResolver {
    /// The action to run, or nil when the action is unavailable for this app.
    /// Other kinds of action are returned as they are.
    public static func resolve(_ action: Config.Action, frontApp: String?,
                               contexts: [Config.Context]) -> Config.Action? {
        guard case let .contextual(variants, fallback) = action else { return action }
        if let frontApp {
            // The first context, in `contexts` order, that has the app and a variant.
            for context in contexts where context.apps.contains(frontApp) {
                if let variant = variants[context.id] { return variant }
            }
        }
        return fallback
    }
}

extension LoadedConfig {
    /// False for a Context Aware binding with nothing to run for this app.
    public func isAvailable(_ binding: BindingNode, frontApp: String?) -> Bool {
        guard let id = binding.action, let action = config.actions[id] else { return true }
        return ContextResolver.resolve(action, frontApp: frontApp, contexts: config.contexts) != nil
    }
}
