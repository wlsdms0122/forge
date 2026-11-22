//
//  LiveAgent.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// The live agent seam over forge's invoke executor. The session is ambient —
// `withSession` binds it to the task and `send` speaks through whatever session
// the current task carries, so the session follows structured concurrency's
// task-local scoping.
struct LiveAgent: AgentServing {
    // MARK: - Property
    private static let category = "session"

    let executor: AgentExecutor
    let sessions: SessionStore

    // MARK: - Initializer
    init(executor: AgentExecutor, sessions: SessionStore) {
        self.executor = executor
        self.sessions = sessions
    }

    // MARK: - Public
    func withSession(
        _ settings: AgentSessionSettings,
        body: @Sendable () async throws -> Warp.Value
    ) async throws -> Warp.Value {
        // share_session is a conditional join: settings ride along as the
        // pre-injection for the fallback — with an outer session they are
        // ignored and the body joins it, without one they open a new session.
        // Callers cannot know at authoring time which side they will land on.
        if settings.shareSession, AgentSession.current != nil {
            return try await body()
        }

        // An invoke around this one already holds the name, so waiting for it
        // would wait for this task itself.
        if let name = settings.session, let held = AgentSession.held[name] {
            return try await AgentSession.$current.withValue(held) {
                try await body()
            }
        }

        if let name = settings.session, AgentSession.heldAroundFanOut.contains(name) {
            throw RunRefused(
                "invoke: session '\(name)' is held by an invoke around this fan-out,"
                    + " which waits for this piece — a piece cannot enter it"
            )
        }

        // A session without a name ends with this invoke, and no other invoke can ask for it.
        guard let name = settings.session else {
            return try await bind(try open(settings), body: body)
        }

        try await sessions.acquire(name)

        do {
            let session = try await enter(name: name, settings: settings)
            let value = try await bind(session, body: body)

            await sessions.release(name)

            return value
        } catch {
            await sessions.release(name)

            throw error
        }
    }

    func send(prompt: String) async throws -> String {
        guard let session = AgentSession.current else {
            throw AgentSessionMissing(
                "agent step has no active agent session — run it inside an `invoke`'s"
                    + " steps (directly, or via dispatch from within one)"
            )
        }

        return try await LogContext.childNode {
            let result: AgentInvocationResult

            do {
                result = try await turn(prompt, in: session)
            } catch let lost as BackendSessionLost {
                // Only a kept session's first turn can find the conversation
                // gone and start over; later, the body has turns in it that a
                // new conversation would not hold.
                guard case let .record(record, name, isConfirmed: false) = session.keeping else {
                    throw lost.exit
                }

                try await renew(session, named: name, from: record)
                result = try await turn(prompt, in: session)
            }

            try await keep(session, after: result)

            return result.text
        }
    }

    // MARK: - Private
    private static func agent(from settings: AgentSessionSettings) throws -> Agent {
        try agent(
            model: settings.model,
            allowed: try settings.allowed?.map(ValueBridge.json),
            permissionMode: settings.permissionMode,
            settings: settings
        )
    }

    // The model, the tools and the permission mode are the session's; the
    // working directory and the environment are each invoke's own.
    private static func agent(
        model: String?,
        allowed: [JSONValue]?,
        permissionMode: String?,
        settings: AgentSessionSettings
    ) throws -> Agent {
        let mode: PermissionMode?

        if let raw = permissionMode {
            guard let known = PermissionMode(rawValue: raw) else {
                throw AgentValidationError(
                    "invoke: permission_mode must be one of bypass/safe/restrict, got \(raw)"
                )
            }

            mode = known
        } else {
            mode = nil
        }

        let environment = SubprocessEnv.merge(
            baseline: SubprocessEnv.baseline(accessToken: WorkflowExecutionState.accessToken),
            specOverride: settings.envExtra
        ) ?? [:]

        return try Agent(
            model: model,
            allowed: try allowed?.map(AgentToolReference.decode),
            workingDirectory: settings.cwd,
            environment: environment,
            permissionMode: mode
        )
    }

    private func bind(
        _ session: AgentSession,
        body: @Sendable () async throws -> Warp.Value
    ) async throws -> Warp.Value {
        var held = AgentSession.held

        if let name = session.name { held[name] = session }

        return try await AgentSession.$current.withValue(session) {
            try await AgentSession.$held.withValue(held) {
                try await body()
            }
        }
    }

    // A session that ends with its invoke, on the backend the settings name.
    private func open(_ settings: AgentSessionSettings) throws -> AgentSession {
        let agent = try Self.agent(from: settings)
        let backend = try executor.backends.resolve(provider: agent.provider)

        return AgentSession(
            agent: agent,
            backend: backend,
            handle: backend.openSession(),
            keeping: .none
        )
    }

    // The session a name stands for: the kept one where there is a record, a
    // new one from this invoke's settings where there is none.
    private func enter(name: SessionName, settings: AgentSessionSettings) async throws -> AgentSession {
        guard let record = try await sessions.record(name) else {
            let session = try open(settings)
            let now = ISO8601.string(Date())

            session.keeping = .record(
                SessionRecord(
                    provider: try executor.backends.name(provider: session.agent.provider),
                    handle: try session.backend.record(of: session.handle),
                    model: settings.model,
                    allowed: try settings.allowed?.map(ValueBridge.json),
                    permissionMode: settings.permissionMode,
                    createdAt: now,
                    usedAt: now,
                    turns: 0
                ),
                name: name,
                isConfirmed: true
            )

            return session
        }

        // A session made without a model still runs on the backend its record
        // names, whatever is registered by now.
        let backend = try executor.backends.resolve(provider: record.provider)
        let agent = try Self.agent(
            model: record.model ?? record.provider,
            allowed: record.allowed,
            permissionMode: record.permissionMode,
            settings: settings
        )

        return AgentSession(
            agent: agent,
            backend: backend,
            handle: try backend.session(from: record.handle),
            keeping: .record(record, name: name, isConfirmed: false)
        )
    }

    private func turn(_ prompt: String, in session: AgentSession) async throws -> AgentInvocationResult {
        let invocation = AgentInvocation(
            id: UUID().uuidString,
            agent: session.agent,
            prompt: prompt,
            session: session.handle
        )

        guard let name = session.name else { return try await executor.run(invocation) }

        // The turn's log entries say which kept session they belong to.
        var metadata = LogContext.metadata?.dict ?? [:]
        metadata["session"] = name.rawValue

        return try await LogContext.$metadata.withValue(LogPayload(metadata)) {
            try await executor.run(invocation)
        }
    }

    // The backend lost the conversation, so the name starts a new one.
    private func renew(
        _ session: AgentSession,
        named name: SessionName,
        from record: SessionRecord
    ) async throws {
        session.handle = session.backend.openSession()
        session.keeping = .record(
            record.restarted(
                handle: try session.backend.record(of: session.handle),
                at: ISO8601.string(Date())
            ),
            name: name,
            isConfirmed: true
        )

        await Log.shared.append(
            "session.lost",
            LogPayload(["session": name.rawValue, "provider": record.provider]),
            category: Self.category
        )
    }

    // The record follows each turn, so a daemon that stops mid-invoke leaves
    // the session where its last finished turn left it.
    private func keep(_ session: AgentSession, after result: AgentInvocationResult) async throws {
        guard case .record(var record, let name, _) = session.keeping else { return }

        record.handle = try session.backend.record(of: session.handle)
        record.usedAt = ISO8601.string(Date())
        record.turns += 1
        record.contextTokens = result.contextTokens ?? record.contextTokens
        session.keeping = .record(record, name: name, isConfirmed: true)

        try await sessions.write(record, for: name)
    }
}
