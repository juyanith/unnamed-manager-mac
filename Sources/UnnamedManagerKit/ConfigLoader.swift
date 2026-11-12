import Foundation

/// Reads the config file and turns every failure into sentences (S-001).
public enum ConfigLoader {
    /// Decodes and validates JSON data. Tests pass a registry with families of their own.
    public static func load(_ data: Data, registry: ActionRegistry = .standard) -> Result<LoadedConfig, ConfigErrors> {
        let config: Config
        do {
            let decoder = JSONDecoder()
            decoder.userInfo[ActionRegistry.userInfoKey] = registry
            config = try decoder.decode(Config.self, from: data)
        } catch {
            return .failure(ConfigErrors(issues: [ConfigIssue(.error, describe(error), rule: rule(for: error))]))
        }
        return ConfigValidator.validate(config)
    }

    /// Reads the file. A missing file is an error here; the app writes the
    /// starter config first (`writeStarterIfMissing`).
    public static func load(contentsOf url: URL) -> Result<LoadedConfig, ConfigErrors> {
        do {
            return load(try Data(contentsOf: url))
        } catch {
            return .failure(ConfigErrors(issues: [ConfigIssue(.error, "Unable to read \(url.path): \(error.localizedDescription)")]))
        }
    }

    /// Writes the starter config when no file exists. Never writes over a
    /// file. Returns true when it wrote one.
    @discardableResult
    public static func writeStarterIfMissing(at url: URL) throws -> Bool {
        let files = FileManager.default
        guard !files.fileExists(atPath: url.path) else { return false }
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(starterJSON.utf8).write(to: url, options: .withoutOverwriting)
        return true
    }

    /// Writes config.schema.json next to the config when it's missing or
    /// out of date, so the starter's "$schema" line finds it (S-039).
    public static func writeSchema(nextTo configURL: URL) throws {
        let url = configURL.deletingLastPathComponent().appending(path: ConfigSchema.fileName)
        let data = Data(ConfigSchema.json.utf8)
        guard (try? Data(contentsOf: url)) != data else { return }
        try data.write(to: url, options: .atomic)
    }

    /// One leader with two bindings, and Hyper+H for Help (S-001, S-053).
    public static let starterJSON = """
    {
      "$schema": "./config.schema.json",
      "version": 1,
      "entries": [
        { "keys": "Hyper+Space", "title": "Commands" },
        { "keys": "Hyper+Space F", "title": "Finder", "action": "open-finder" },
        { "keys": "Hyper+Space T", "title": "Terminal", "action": "open-terminal" },
        { "keys": "Hyper+H", "title": "Help", "action": "show-help" }
      ],
      "actions": {
        "open-finder": { "type": "application", "bundleId": "com.apple.finder" },
        "open-terminal": { "type": "application", "bundleId": "com.apple.Terminal" },
        "show-help": { "type": "help" }
      }
    }

    """

    /// The spec rule a decoding error breaks (S-059).
    static func rule(for error: any Error) -> ConfigRule {
        if error is UnknownFieldError { return .unknownField }
        switch error as? DecodingError {
        case .keyNotFound: return .missingField
        case .typeMismatch, .valueNotFound: return .wrongType
        case let .dataCorrupted(context):
            if let marker = context.underlyingError as? RuleMarker { return marker.rule }
            return context.codingPath.isEmpty ? .invalidJSON : .wrongType
        default: return .invalidJSON
        }
    }

    /// A decoding error as one sentence that names where the problem is.
    static func describe(_ error: any Error) -> String {
        if let unknown = error as? UnknownFieldError {
            return "Unknown field “\(unknown.field)” in \(unknown.path). Check its spelling, or remove it."
        }
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        switch decoding {
        case let .keyNotFound(key, context):
            return "Missing “\(key.stringValue)” in \(place(context.codingPath))."
        case let .typeMismatch(type, context), let .valueNotFound(type, context):
            return "“\(context.codingPath.last?.stringValue ?? "value")” in \(place(context.codingPath.dropLast())) should be \(kind(type))."
        case let .dataCorrupted(context):
            if context.codingPath.isEmpty {
                let detail = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
                return "The config file isn't valid JSON\(detail.map { ": \($0)" } ?? ".")"
            }
            return "\(context.debugDescription) (in \(place(context.codingPath)))"
        @unknown default:
            return decoding.localizedDescription
        }
    }

    private static func place(_ path: some Collection<any CodingKey>) -> String {
        guard !path.isEmpty else { return "the file" }
        return path.map { key in
            if let index = key.intValue { return "item \(index + 1)" }
            return key.stringValue
        }.joined(separator: " › ")
    }

    private static func kind(_ type: Any.Type) -> String {
        switch type {
        case is String.Type: "text in quotes"
        case is Int.Type: "a whole number"
        case is Bool.Type: "true or false"
        case is [String].Type: "a list of text"
        default: "a different kind of value"
        }
    }
}
