//
//  InvokeAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// The agent session envelope. It resolves the session
// settings (model, permissions, cwd, ...) at its boundary, opens the ambient
// session through the environment, and runs its steps inside; `agent` steps only make
// sense in here.
struct InvokeAction: ForgeAction {
    enum Parameters: Int, ParameterSet {
        case model
        case allowed
        case envExtra
        case cwd
        case permissionMode
        case shareSession
        case session
        case onSessionStart
        case onContextStart
        case compact
        case compactMode
        case timeout
        case body

        // MARK: - Property
        var declared: Parameter {
            switch self {
            case .model:
                Parameter(name: "model", type: .optional(.string))

            case .allowed:
                Parameter(name: "allowed", type: .optional(.array(.any)))

            case .envExtra:
                Parameter(name: "env_extra", type: .dictionary(key: .string, value: .string))

            case .cwd:
                Parameter(name: "cwd", type: .optional(.string))

            case .permissionMode:
                Parameter(name: "permission_mode", type: .optional(.string))

            case .shareSession:
                Parameter(name: "share_session", type: .bool)

            case .session:
                Parameter(name: "session", type: .optional(.string))

            case .onSessionStart:
                Parameter(
                    name: "on_session_start",
                    type: .optional(.procedure(ProcedureType(returns: .null, failing: .anything)))
                )

            case .onContextStart:
                Parameter(
                    name: "on_context_start",
                    type: .optional(.procedure(ProcedureType(returns: .null, failing: .anything)))
                )

            case .compact:
                Parameter(name: "compact", type: .named(ForgeVocabulary.compactionType))

            case .compactMode:
                Parameter(name: "compact_mode", type: .named(ForgeVocabulary.compactionModeType))

            case .timeout:
                Parameter(name: "timeout", type: .optional(.double))

            case .body:
                Parameter(
                    name: "body",
                    type: .procedure(ProcedureType(returns: InvokeAction.result, failing: .anything))
                )
            }
        }

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    // What the body returns, which is what the session returns.
    static let result = TypeExpression.parameter(name: "Result")

    static let signature = Signature(of: Self.self, returns: result, failing: .anything, isolation: .isolated)

    // MARK: - Initializer
    // MARK: - Public
    func act(_ invocation: Invocation<Self>, in environment: ForgeEnvironment) async throws -> Warp.Value {
        // The body is a closure so that nothing in it runs before the session
        // is open.
        guard case let .procedure(body) = invocation[.body] else {
            throw RunRefused("invoke has no body")
        }

        let settings = AgentSessionSettings(
            model: invocation.string(.model),
            allowed: Self.items(invocation[.allowed]),
            cwd: try Self.nonEmpty(invocation.string(.cwd), field: "cwd"),
            permissionMode: try Self.nonEmpty(invocation.string(.permissionMode), field: "permission_mode"),
            envExtra: try ValueBridge.strings(invocation[.envExtra]),
            shareSession: invocation[.shareSession] == .bool(true),
            session: try Self.nonEmpty(invocation.string(.session), field: "session").map(SessionName.init),
            compact: try Self.compaction(invocation[.compact]),
            compactMode: try Self.compactionMode(invocation[.compactMode])
        )

        // Both say which session the body speaks through, so they cannot both stand.
        guard !(settings.shareSession && settings.session != nil) else {
            throw RunRefused("invoke: session and share_session: true cannot be given together")
        }

        let lifecycle = AgentSessionLifecycle(
            onSessionStart: Self.hook(.onSessionStart, of: invocation),
            onContextStart: Self.hook(.onContextStart, of: invocation)
        )

        return try await Deadline(seconds: ValueBridge.number(invocation[.timeout])).run {
            try await environment.capabilities.agent.withSession(settings, lifecycle: lifecycle) {
                try await invocation.call(body)
            }
        }
    }

    // MARK: - Private
    private static func hook(
        _ parameter: Parameters,
        of invocation: Invocation<Self>
    ) -> AgentSessionLifecycle.Hook? {
        guard case let .procedure(procedure) = invocation[parameter] else { return nil }

        return { _ = try await invocation.call(procedure) }
    }

    private static func compaction(_ value: Warp.Value) throws -> CompactionPolicy {
        guard case let .struct(compaction) = value else {
            throw RunRefused("invoke: compact is no case of \(ForgeVocabulary.compactionType)")
        }

        // A value of an enum carries its case's spelling.
        let auto: Warp.Name = "Forge.Compaction.auto"
        let none: Warp.Name = "Forge.Compaction.none"

        if compaction.name == auto { return .automatic }
        if compaction.name == none { return .none }

        guard case let .int(tokens)? = compaction.values.first, tokens > 0 else {
            throw RunRefused("invoke: compact's limit must be above 0 tokens")
        }

        return .limit(tokens)
    }

    private static func compactionMode(_ value: Warp.Value) throws -> CompactionMode {
        // A value of an enum carries its case's spelling, whose last part is the case.
        guard
            case let .struct(written) = value,
            let name = written.name.description.split(separator: ".").last,
            let mode = CompactionMode(rawValue: String(name))
        else {
            throw RunRefused("invoke: compact_mode is no case of \(ForgeVocabulary.compactionModeType)")
        }

        return mode
    }

    // null means "unset" and stays nil, and the signature holds the rest to a list.
    private static func items(_ value: Warp.Value) -> [Warp.Value]? {
        guard case let .array(items) = value else { return nil }

        return items
    }

    // null means "unset" and stays nil; an empty string is an author mistake, not
    // a quiet fallback into what unset means.
    private static func nonEmpty(_ string: String?, field: String) throws -> String? {
        guard string != "" else {
            throw RunRefused(
                "invoke: \(field) must be a non-empty string, or omitted/null to"
                    + " mean \"unset\" — got an empty string"
            )
        }

        return string
    }
}
