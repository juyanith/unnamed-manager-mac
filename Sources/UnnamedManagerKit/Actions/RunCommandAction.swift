import Foundation

/// Run Command (S-011): starts a program directly, with no shell.
public struct RunCommandAction: ActionValue {
    /// The program, then its arguments.
    public var command: [String]
    /// The working folder; nil is the home folder.
    public var cwd: String?
    /// Added to the inherited environment.
    public var env: [String: String]

    public init(command: [String], cwd: String? = nil, env: [String: String] = [:]) {
        self.command = command
        self.cwd = cwd
        self.env = env
    }

    public static let kinds = [ActionKind(type: "exec", displayName: "Run Command")]

    public var type: String { "exec" }

    public static func blank(_ type: String) -> RunCommandAction {
        RunCommandAction(command: [])
    }

    public init(type: String, fields: ActionFields) throws {
        try fields.allow(["command", "cwd", "env"])
        command = try fields.required("command")
        cwd = try fields.optional("cwd")
        env = try fields.value("env", default: [:])
    }

    public func write(to fields: inout ActionFieldWriter) {
        fields.strings("command", command)
        if let cwd { fields.string("cwd", cwd) }
        if !env.isEmpty { fields.dictionary("env", env) }
    }

    public static func schema(_ type: String) -> ActionSchema {
        ActionSchema([
            "command": ["type": "array", "items": ["type": "string"], "minItems": 1],
            "cwd": ["type": "string"],
            "env": ["type": "object", "additionalProperties": ["type": "string"]],
        ], required: ["command"])
    }

    /// Arguments are passed literally; only a leading ~ is expanded.
    public func plan(home: URL) throws(PlanError) -> ActionPlan {
        guard let program = command.first, !program.isEmpty else {
            throw PlanError("Run Command needs a program as the first item of “command”.")
        }
        let arguments = command.dropFirst().map { ActionPlanner.expandTilde($0, home: home) }
        let directory = cwd.map { URL(fileURLWithPath: ActionPlanner.expandTilde($0, home: home), isDirectory: true) } ?? home
        return .spawn(program: ActionPlanner.expandTilde(program, home: home), arguments: Array(arguments), cwd: directory, env: env)
    }
}
