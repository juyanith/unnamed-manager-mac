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
        if config.windows != Config.Windows(maxColumns: config.windows.maxColumns, maxRows: config.windows.maxRows) {
            let standard = Config.Windows()
            var fields = ActionFieldWriter()
            if config.windows.gap != standard.gap { fields.number("gap", config.windows.gap) }
            // maxColumns and maxRows are retired (spec v24), so they're dropped.
            func steps(_ value: WindowSteps) -> ActionFieldWriter {
                var each = ActionFieldWriter()
                each.number("across", Double(value.across))
                each.number("down", Double(value.down))
                return each
            }
            if config.windows.minCell != standard.minCell { fields.object("minCell", steps(config.windows.minCell)) }
            if !config.windows.displays.isEmpty {
                var displays = ActionFieldWriter()
                for (key, display) in config.windows.displays.sorted(by: { $0.key < $1.key }) {
                    var each = ActionFieldWriter()
                    if let value = display.steps { each.object("steps", steps(value)) }
                    if let value = display.minCell { each.object("minCell", steps(value)) }
                    displays.object(key, each)
                }
                fields.object("displays", displays)
            }
            if config.windows.minVisible != standard.minVisible { fields.number("minVisible", config.windows.minVisible) }
            if config.windows.rowTolerance != standard.rowTolerance { fields.number("rowTolerance", config.windows.rowTolerance) }
            if config.windows.tieTolerance != standard.tieTolerance { fields.number("tieTolerance", config.windows.tieTolerance) }
            if config.windows.quitOnClose != standard.quitOnClose { fields.bool("quitOnClose", config.windows.quitOnClose) }
            if config.windows.quitOnCloseDelayMs != standard.quitOnCloseDelayMs {
                fields.number("quitOnCloseDelayMs", Double(config.windows.quitOnCloseDelayMs))
            }
            if !config.windows.apps.isEmpty {
                // Every rule of every app listed, so the file reads like the table in Settings.
                var apps = ActionFieldWriter()
                for (app, rules) in config.windows.apps.sorted(by: { $0.key < $1.key }) {
                    var each = ActionFieldWriter()
                    each.bool("focus", rules.focus)
                    each.bool("swap", rules.swap)
                    each.bool("arrange", rules.arrange)
                    each.bool("quit", rules.quit)
                    if rules.minWidth != 0 { each.number("minWidth", rules.minWidth) }
                    if rules.minHeight != 0 { each.number("minHeight", rules.minHeight) }
                    apps.object(app, each)
                }
                fields.object("apps", apps)
            }
            sections.append("  \"windows\": \(object(fields.fields))")
        }
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
        if entry.hold { fields.append(("hold", "true")) }
        if let list = entry.list { fields.append(("list", self.list(list))) }
        return object(fields)
    }

    /// A list with its defaults left out.
    private static func list(_ list: Config.List) -> String {
        let d = Config.List()
        var fields = [("type", quote(list.type))]
        if list.count != d.count { fields.append(("count", "\(list.count)")) }
        // What the file has: a field that was written stays written.
        if let minimized = list.minimized { fields.append(("minimized", "\(minimized)")) }
        if let hidden = list.hidden { fields.append(("hidden", "\(hidden)")) }
        if let spaces = list.spaces { fields.append(("spaces", quote(spaces))) }
        if list.scope != d.scope { fields.append(("scope", quote(list.scope))) }
        if list.choose != d.choose { fields.append(("choose", quote(list.choose))) }
        return object(fields)
    }

    private static func context(_ context: Config.Context) -> String {
        object([("id", quote(context.id)), ("apps", "[" + context.apps.map(quote).joined(separator: ", ") + "]")])
    }

    static func action(_ action: Config.Action, contexts: [Config.Context]) -> String {
        var fields = [("type", quote(action.type))]
        switch action {
        case let .contextual(variants, fallback):
            // Variants follow the contexts' order, which decides which one wins.
            let ids = ordered(Array(variants.keys), by: contexts.map(\.id))
            fields.append(("variants", object(ids.map { ($0, self.action(variants[$0]!, contexts: contexts)) })))
            if let fallback { fields.append(("fallback", self.action(fallback, contexts: contexts))) }
        case let .family(value):
            var writer = ActionFieldWriter()
            value.value.write(to: &writer)
            fields += writer.fields
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
