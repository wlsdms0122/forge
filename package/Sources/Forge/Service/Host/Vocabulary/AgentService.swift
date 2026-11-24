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
    let summaryCompaction: SummaryCompaction

    // MARK: - Initializer
    init(
        executor: AgentExecutor,
        sessions: SessionStore,
        limits: ForgeConfig.SessionConfig = ForgeConfig.SessionConfig(),
        summaryCompaction: SummaryCompaction = SummaryCompaction()
    ) {
        self.executor = executor
        self.sessions = sessions
        self.limits = limits
        self.summaryCompaction = summaryCompaction
    }

    // MARK: - Public
    func withSession(
        _ settings: AgentSessionSettings,
        lifecycle: AgentSessionLifecycle,
        body: @Sendable () async throws -> Warp.Value
    ) async throws -> Warp.Value {
        // share_session is a conditional join: settings ride along as the
        // pre-injection for the fallback — with an outer session they are
        // ignored and the body joins it, without one they open a new session.
        // Callers cannot know at authoring time which side they will land on.
        if settings.shareSession, let current = AgentSession.current {
            return try await bind(current.session, lifecycle: lifecycle.joining(current.lifecycle), body: body)
        }

        // An invoke around this one already holds the name, so waiting for it
        // would wait for this task itself.
        if let name = settings.session, let held = AgentSession.held[name] {
            return try await bind(held.session, lifecycle: lifecycle.joining(held.lifecycle), body: body)
        }

        if let name = settings.session, AgentSession.heldAroundFanOut.contains(name) {
            throw RunRefused(
                "invoke: session '\(name)' is held by an invoke around this fan-out,"
                    + " which waits for this piece — a piece cannot enter it"
            )
        }

        // A session without a name ends with this invoke, and no other invoke can ask for it.
        guard let name = settings.session else {
            return try await bind(try open(settings), lifecycle: lifecycle, body: body)
        }

        try await sessions.acquire(name)

        do {
            let session = try await enter(name: name, settings: settings)
            let value = try await bind(session, lifecycle: lifecycle, body: body)

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

    func compact(slots: any StepSlotProviding) async throws -> Bool {
        guard let session = AgentSession.current?.session else {
            throw AgentSessionMissing(
                "compact step has no active agent session — run it inside an `invoke`'s"
                    + " steps (directly, or via dispatch from within one)"
            )
        }

        // A conversation no turn has gone into holds nothing to compact.
        guard session.usedAt != nil, session.summary == nil else { return false }

        return try await LogContext.childNode {
            do {
                try await compact(session, for: .requested, slots: slots)
            } catch let lost as BackendSessionLost {
                // As a turn does: only a kept session's first step can find
                // the conversation gone, and the new one holds nothing yet.
                guard case let .record(record, name, isConfirmed: false) = session.keeping else {
                    throw lost.exit
                }

                try await renew(session, named: name, from: record)

                return false
            }

            return true
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

    // The body speaks through the session with this lifecycle.
    private func bind(
        _ session: AgentSession,
        lifecycle: AgentSessionLifecycle,
        body: @Sendable () async throws -> Warp.Value
    ) async throws -> Warp.Value {
        let binding = AgentSessionBinding(session: session, lifecycle: lifecycle)
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

        guard settings.compactMode != .provider || backend is any CompactingBackend else {
            throw AgentValidationError(
                "invoke: compact_mode is provider, and \(try executor.backends.name(provider: agent.provider))"
                    + " has no compaction of its own"
            )
        }

        return AgentSession(
            agent: agent,
            backend: backend,
            compaction: settings.compact,
            compactionMode: settings.compactMode,
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
                    compact: settings.compact,
                    compactMode: settings.compactMode
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
            compaction: record.compact,
            compactionMode: record.compactMode,
            handle: try backend.session(from: record.handle),
            keeping: .record(record, name: name, isConfirmed: false),
            contextTokens: record.contextTokens,
            usedAt: ISO8601.parse(record.usedAt),
            due: record.due,
            summary: record.summary
        )
    }

    private func turn(_ prompt: String, in session: AgentSession) async throws -> AgentInvocationResult {
        let invocation = AgentInvocation(
            id: UUID().uuidString,
            agent: session.agent,
            prompt: session.summary.map { summary in summaryCompaction.opening(prompt, after: summary) } ?? prompt,
            session: session.handle
        )
        let result = try await logged(in: session) { try await executor.run(invocation) }

        // The conversation that took the prompt took the summary with it.
        session.summary = nil

        return result
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
        // Both events happened again. A hook this happens during runs its
        // turns in the new conversation, so its event is not due once more.
        session.due = Set(AgentSessionEvent.allCases).subtracting([session.running].compactMap { event in event })
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
    // slot; the hooks between them hold none, since their own turns take theirs.
    private func deliver(
        _ prompt: String,
        through binding: AgentSessionBinding,
        slots: any StepSlotProviding
    ) async throws -> AgentInvocationResult {
        let session = binding.session

        try await compactIfDue(session, slots: slots)
        try await startIfDue(session, with: binding.lifecycle)

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

    // Runs the hook of each event that is due. A hook's own turns pass through
    // here while it runs, and an invoke that brings no hook for an event
    // leaves it due.
    private func startIfDue(_ session: AgentSession, with lifecycle: AgentSessionLifecycle) async throws {
        guard session.running == nil else { return }

        var ran = false

        for event in AgentSessionEvent.allCases {
            guard session.due.contains(event), let hook = lifecycle.hook(for: event) else { continue }

            // Taken off before the hook runs, so the event happening again
            // during it leaves it due once more.
            session.due.remove(event)
            session.running = event

            do {
                try await hook()
            } catch {
                session.running = nil
                session.due.insert(event)

                throw error
            }

            session.running = nil
            ran = true
        }

        // Hooks whose turns finished are on record before the turn they ran
        // for; ones that sent none have no conversation to keep yet.
        guard ran, case let .record(record, _, _) = session.keeping, record.turns > 0 else { return }

        try await keep(session) { _ in }
    }

    // An invoke that takes up a kept conversation past its sizes compacts it
    // before the first turn. Once the invoke has a turn in it, the body's
    // turns stand on one another and the conversation is left whole.
    private func compactIfDue(_ session: AgentSession, slots: any StepSlotProviding) async throws {
        guard
            case .record(_, _, isConfirmed: false) = session.keeping,
            let reason = compactionReason(for: session)
        else {
            return
        }

        try await compact(session, for: reason, slots: slots)
    }

    private func compact(
        _ session: AgentSession,
        for reason: CompactionReason,
        slots: any StepSlotProviding
    ) async throws {
        let result = try await slots.withStepSlot {
            try await logged(in: session) {
                guard let backend = session.compactingBackend else { return try await summarize(session) }

                return try await executor.compact(session.handle, agent: session.agent, on: backend)
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

    // Forge's own compaction. The size the summarizing turn measured is the
    // old conversation's, so the new one has none until a turn reports it.
    private func summarize(_ session: AgentSession) async throws -> AgentInvocationResult {
        let result = try await executor.run(
            AgentInvocation(
                id: UUID().uuidString,
                agent: session.agent,
                prompt: summaryCompaction.request,
                session: session.handle,
                isSummaryRequest: true
            )
        )

        session.summary = try summaryCompaction.summary(in: result.text)
        session.handle = session.backend.openSession()

        return AgentInvocationResult(
            text: result.text,
            usage: result.usage,
            toolEvents: result.toolEvents,
            durationMs: result.durationMs,
            isCompacted: true
        )
    }

    // A summary stands where the context a hook built was, and the
    // conversation is as large as the turns after the cut measured it.
    private func compacted(
        _ session: AgentSession,
        by result: AgentInvocationResult,
        reason: CompactionReason
    ) async {
        var payload: [String: Any] = [
            "reason": reason.rawValue,
            "by": session.summary == nil ? "provider" : "builtin",
            "duration_ms": result.durationMs
        ]

        if let size = session.contextTokens { payload["context_tokens"] = size }
        if let name = session.name { payload["session"] = name.rawValue }

        session.contextTokens = result.contextTokens
        session.due.insert(.contextStart)

        await Log.shared.append("session.compacted", LogPayload(payload), category: Self.category)
    }

    private func compactionReason(for session: AgentSession) -> CompactionReason? {
        guard let size = session.contextTokens else { return nil }

        let limit: Int

        switch session.compaction {
        case .automatic:
            limit = limits.contextLimit

        case .none:
            return nil

        case let .limit(own):
            limit = own
        }

        if size > limit { return .limit }

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
        // A hook still running has not finished what its event calls for.
        record.due = session.due.union([session.running].compactMap { event in event })
        record.summary = session.summary
        change(&record)
        session.keeping = .record(record, name: name, isConfirmed: true)

        try await sessions.write(record, for: name)
    }
}
