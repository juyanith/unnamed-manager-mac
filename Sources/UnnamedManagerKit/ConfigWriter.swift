import Foundation

/// Writes a config as JSON with a fixed layout (S-033): the same key order
/// every time, one line per entry, action and context, and defaults left
/// out, so an edit changes only the lines it touches.
public enum ConfigWriter {
    public static func write(_ config: Config, actionOrder: [String]) -> String {
        var sections: [String] = []
        if let schema = config.schema { sections.append("  \"$schema\": \(quote(schema))") }
        sections.append("  \"version\": \(config.version)")
        if let runtime = runtimeFields(config.runtime) { sections.append("  \"runtime\": \(runtime)") }
        if let ui = uiFields(config.ui) { sections.append("  \"ui\": \(ui)") }
        sections.append(list("entries", config.entries.map(entry)))
        if !config.actions.isEmpty {
            let ids = ordered(Array(config.actions.keys), by: actionOrder)
            let lines = ids.map { "    \(quote($0)): \(action(config.actions[$0]!, contexts: config.contexts))" }
            sections.append("  \"actions\": {\n" + lines.joined(separator: ",\n") + "\n  }")
        }
        if !config.contexts.isEmpty {
            sections.append(list("contexts", config.contexts.map(context)))
        }
        return "{\n" + sections.joined(separator: ",\n") + "\n}\n"
    }

    /// `ids` in the order given, then any others sorted, so nothing is lost.
    static func ordered(_ ids: [String], by order: [String]) -> [String] {
        let known = order.filter(ids.contains)
        return known + ids.filter { !known.contains($0) }.sorted()
    }

    private static func list(_ name: String, _ lines: [String]) -> String {
        "  \(quote(name)): [\n" + lines.map { "    " + $0 }.joined(separator: ",\n") + "\n  ]"
    }

    static func object(_ fields: [(String, String)]) -> String {
        "{ " + fields.map { "\(quote($0.0)): \($0.1)" }.joined(separator: ", ") + " }"
    }

    private static func entry(_ entry: Config.Entry) -> String {
        var fields = [("keys", quote(entry.keys)), ("title", quote(entry.title))]
        if let action = entry.action { fields.append(("action", quote(action))) }
        if let icon = entry.icon { fields.append(("icon", quote(icon))) }
        return object(fields)
    }

    private static func context(_ context: Config.Context) -> String {
        object([("id", quote(context.id)), ("apps", "[" + context.apps.map(quote).joined(separator: ", ") + "]")])
    }

    static func action(_ action: Config.Action, contexts: [Config.Context]) -> String {
        var fields = [("type", quote(action.type))]
        switch action {
        case let .application(bundleId, mode):
            fields.append(("bundleId", quote(bundleId)))
            if mode != .default { fields.append(("mode", quote(mode.rawValue))) }
        case let .open(target):
            fields.append(("target", quote(target)))
        case let .exec(command, cwd, env):
            fields.append(("command", "[" + command.map(quote).joined(separator: ", ") + "]"))
            if let cwd { fields.append(("cwd", quote(cwd))) }
            if !env.isEmpty {
                fields.append(("env", object(env.keys.sorted().map { ($0, quote(env[$0]!)) })))
            }
        case let .send(keys):
            fields.append(("keys", quote(keys)))
        case let .contextual(variants, fallback):
            // Variants follow the contexts' order, which decides which one wins.
            let ids = ordered(Array(variants.keys), by: contexts.map(\.id))
            fields.append(("variants", object(ids.map { ($0, self.action(variants[$0]!, contexts: contexts)) })))
            if let fallback { fields.append(("fallback", self.action(fallback, contexts: contexts))) }
        case .noop, .help:
            break
        }
        return object(fields)
    }

    private static func runtimeFields(_ runtime: Config.Runtime) -> String? {
        let d = Config.Runtime()
        var fields: [(String, String)] = []
        if runtime.cancelKey != d.cancelKey { fields.append(("cancelKey", quote(runtime.cancelKey))) }
        if runtime.backKey != d.backKey { fields.append(("backKey", quote(runtime.backKey))) }
        if runtime.showHud != d.showHud { fields.append(("showHud", "\(runtime.showHud)")) }
        if runtime.hudDelayMs != d.hudDelayMs { fields.append(("hudDelayMs", "\(runtime.hudDelayMs)")) }
        if runtime.timeoutMs != d.timeoutMs { fields.append(("timeoutMs", "\(runtime.timeoutMs)")) }
        return fields.isEmpty ? nil : object(fields)
    }

    private static func uiFields(_ ui: Config.UI) -> String? {
        let d = Config.UI()
        var fields: [(String, String)] = []
        if ui.theme != d.theme { fields.append(("theme", quote(ui.theme))) }
        if ui.position != d.position { fields.append(("position", quote(ui.position))) }
        if ui.errorFlash != d.errorFlash { fields.append(("errorFlash", "\(ui.errorFlash)")) }
        if ui.errorBell != d.errorBell { fields.append(("errorBell", "\(ui.errorBell)")) }
        return fields.isEmpty ? nil : object(fields)
    }

    /// A JSON string literal, with slashes left alone.
    static func quote(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return String(decoding: (try? encoder.encode(text)) ?? Data("\"\"".utf8), as: UTF8.self)
    }
}
