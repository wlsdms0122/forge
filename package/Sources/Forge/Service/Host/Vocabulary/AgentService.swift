//
//  AgentService.swift
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
struct AgentService: AgentServing {
    // MARK: - Property
    private static let category = "session"

    let executor: AgentExecutor
    let sessions: SessionStore
    let limits: ForgeConfig.SessionConfig

    // MARK: - Initializer
    init(
        executor: AgentExecutor,
        sessions: SessionStore,
        limits: ForgeConfig.SessionConfig = ForgeConfig.SessionConfig()
    ) {
        self.executor = executor
        self.sessions = sessions
        self.limits = limits
    }

    // MARK: - Public
    func withSession(
        _ settings: AgentSessionSettings,
        setup: (@Sendable () async throws -> Void)?,
        body: @Sendable () async throws -> Warp.Value
    ) async throws -> Warp.Value {
        // share_session is a conditional join: settings ride along as the
        // pre-injection for the fallback — with an outer session they are
        // ignored and the body joins it, without one they open a new session.
        // Callers cannot know at authoring time which side they will land on.
        if settings.shareSession, let current = AgentSession.current {
            return try await bind(current.session, setup: setup ?? current.setup, body: body)
        }

        // An invoke around this one already holds the name, so waiting for it
        // would wait for this task itself.
        if let name = settings.session, let held = AgentSession.held[name] {
            return try await bind(held.session, setup: setup ?? held.setup, body: body)
        }

        if let name = settings.session, AgentSession.heldAroundFanOut.contains(name) {
            throw RunRefused(
                "invoke: session '\(name)' is held by an invoke around this fan-out,"
                    + " which waits for this piece — a piece cannot enter it"
            )
        }

        // A session without a name ends with this invoke, and no other invoke can ask for it.
        guard let name = settings.session else {
            return try await bind(try open(settings), setup: setup, body: body)
        }

        try await sessions.acquire(name)

        do {
            let session = try await enter(name: name, settings: settings)
            let value = try await bind(session, setup: setup, body: body)

            await sessions.release(name)

            return value
        } catch {
            await sessions.release(name)

            throw error
        }
    }

    func send(prompt: String, slots: any StepSlotProviding) async throws -> String {
        guard let binding = AgentSession.current else {
            throw AgentSessionMissing(
                "agent step has no active agent session — run it inside an `invoke`'s"
                    + " steps (directly, or via dispatch from within one)"
            )
        }

        let session = binding.session

        return try await LogContext.childNode {
            let result: AgentInvocationResult

            do {
                result = try await deliver(prompt, through: binding, slots: slots)
            } catch let lost as BackendSessionLost {
                // Only a kept session's first turn can find the conversation
                // gone and start over; later, the body has turns in it that a
                // new conversation would not hold.
                guard case let .record(record, name, isConfirmed: false) = session.keeping else {
                    throw lost.exit
                }

                try await renew(session, named: name, from: record)
                result = try await deliver(prompt, through: binding, slots: slots)
            }

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

    // The body speaks through the session with this setup. An invoke that
    // joins a session an invoke around it holds comes here with that one's
    // setup where it brings none.
    private func bind(
        _ session: AgentSession,
        setup: (@Sendable () async throws -> Void)?,
        body: @Sendable () async throws -> Warp.Value
    ) async throws -> Warp.Value {
        let binding = AgentSessionBinding(session: session, setup: setup)
        var held = AgentSession.held

        if let name = session.name { held[name] = binding }

        return try await AgentSession.$current.withValue(binding) {
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
            compacts: settings.compact,
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
                    turns: 0,
                    compact: settings.compact
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
            compacts: record.compact,
            handle: try backend.session(from: record.handle),
            keeping: .record(record, name: name, isConfirmed: false),
            contextTokens: record.contextTokens,
            usedAt: ISO8601.parse(record.usedAt),
            needsSetup: record.needsSetup
        )
    }

    private func turn(_ prompt: String, in session: AgentSession) async throws -> AgentInvocationResult {
        let invocation = AgentInvocation(
            id: UUID().uuidString,
            agent: session.agent,
            prompt: prompt,
            session: session.handle
        )

        return try await logged(in: session) { try await executor.run(invocation) }
    }

    // The log entries of what runs inside say which kept session they belong to.
    private func logged<Value: Sendable>(
        in session: AgentSession,
        _ operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        guard let name = session.name else { return try await operation() }

        var metadata = LogContext.metadata?.dict ?? [:]
        metadata["session"] = name.rawValue

        return try await LogContext.$metadata.withValue(LogPayload(metadata)) {
            try await operation()
        }
    }

    // The backend lost the conversation, so the name starts a new one.
    private func renew(
        _ session: AgentSession,
        named name: SessionName,
        from record: SessionRecord
    ) async throws {
        session.handle = session.backend.openSession()
        session.contextTokens = nil
        session.usedAt = nil
        // A setup this happens during builds its context in the new conversation.
        session.needsSetup = !session.isSettingUp
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

    // One turn of the session, after whatever the conversation needs first.
    // The compaction and the turn are each an agent process and hold a step
    // slot; the setup between them holds none, since its own turns take theirs.
    private func deliver(
        _ prompt: String,
        through binding: AgentSessionBinding,
        slots: any StepSlotProviding
    ) async throws -> AgentInvocationResult {
        let session = binding.session

        try await compactIfDue(session, slots: slots)
        try await setUpIfDue(session, with: binding.setup)

        let result = try await slots.withStepSlot { try await turn(prompt, in: session) }

        session.usedAt = Date()

        guard result.isCompacted else {
            session.contextTokens = result.contextTokens ?? session.contextTokens

            try await keep(session) { record in record.turns += 1 }

            return result
        }

        await compacted(session, by: result, reason: .turn)

        try await keep(session) { record in
            record.turns += 1
            record.compactions += 1
        }

        return result
    }

    // The setup's own turns pass through here while it runs. An invoke that
    // brings no setup leaves the session in need of one.
    private func setUpIfDue(
        _ session: AgentSession,
        with setup: (@Sendable () async throws -> Void)?
    ) async throws {
        guard session.needsSetup, !session.isSettingUp, let setup else { return }

        // Lowered before the setup runs, so a compaction during it leaves the
        // session in need of another.
        session.needsSetup = false
        session.isSettingUp = true

        do {
            try await setup()
        } catch {
            session.isSettingUp = false
            session.needsSetup = true

            throw error
        }

        session.isSettingUp = false

        // A setup whose turns finished is on record before the turn it ran
        // for; one that sent none has no conversation to keep yet.
        guard case let .record(record, _, _) = session.keeping, record.turns > 0 else { return }

        try await keep(session) { _ in }
    }

    // A turn into a conversation past the daemon's sizes compacts it first.
    private func compactIfDue(_ session: AgentSession, slots: any StepSlotProviding) async throws {
        guard session.compacts, let reason = compactionReason(for: session) else { return }

        let result = try await slots.withStepSlot {
            try await logged(in: session) {
                try await executor.compact(session.handle, agent: session.agent)
            }
        }

        guard result.isCompacted else {
            throw BackendProtocolViolation(
                "the compaction left the conversation as it was"
                    + (session.name.map { name in " (session \(name.rawValue))" } ?? "")
            )
        }

        await compacted(session, by: result, reason: reason)

        try await keep(session) { record in record.compactions += 1 }
    }

    // A summary stands where the context a setup built was, and the
    // conversation is as large as the turns after the cut measured it.
    private func compacted(
        _ session: AgentSession,
        by result: AgentInvocationResult,
        reason: CompactionReason
    ) async {
        var payload: [String: Any] = [
            "reason": reason.rawValue,
            "duration_ms": result.durationMs
        ]

        if let size = session.contextTokens { payload["context_tokens"] = size }
        if let name = session.name { payload["session"] = name.rawValue }

        session.contextTokens = result.contextTokens
        session.needsSetup = true

        await Log.shared.append("session.compacted", LogPayload(payload), category: Self.category)
    }

    private func compactionReason(for session: AgentSession) -> CompactionReason? {
        guard let size = session.contextTokens else { return nil }

        if size > limits.contextLimit { return .limit }

        guard
            size > limits.coldCompactFloor,
            let lifetime = session.backend.cacheLifetime,
            let usedAt = session.usedAt,
            Date().timeIntervalSince(usedAt) > Double(lifetime.components.seconds)
        else {
            return nil
        }

        return .cold
    }

    // The record follows the session, so a daemon that stops mid-invoke leaves
    // the session where its last finished turn left it.
    private func keep(_ session: AgentSession, change: (inout SessionRecord) -> Void) async throws {
        guard case .record(var record, let name, _) = session.keeping else { return }

        record.handle = try session.backend.record(of: session.handle)
        record.usedAt = session.usedAt.map(ISO8601.string) ?? record.usedAt
        record.contextTokens = session.contextTokens
        // A setup still running has not built the context yet.
        record.needsSetup = session.needsSetup || session.isSettingUp
        change(&record)
        session.keeping = .record(record, name: name, isConfirmed: true)

        try await sessions.write(record, for: name)
    }
}
