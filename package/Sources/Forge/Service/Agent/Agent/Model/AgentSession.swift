//
//  AgentSession.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// One invoke's hold on a session. Turns go through a session one at a time,
// so nothing guards the state a turn moves.
final class AgentSession: @unchecked Sendable {
    // MARK: - Property
    // The session the agent turns of the current task speak through.
    @TaskLocal static var current: AgentSession?
    // The sessions the invokes around the current task hold, by name.
    @TaskLocal static var held: [SessionName: AgentSession] = [:]
    // The names held by invokes around a fan-out the current task is a piece
    // of. A piece cannot join them, and waiting for one waits for itself.
    @TaskLocal static var heldAroundFanOut: Set<SessionName> = []

    let agent: Agent
    let backend: any Backend

    var handle: any BackendSession
    var keeping: SessionKeeping

    // The name of a kept session; nil for one that ends with its invoke.
    var name: SessionName? {
        guard case let .record(_, name, _) = keeping else { return nil }

        return name
    }

    // MARK: - Initializer
    init(
        agent: Agent,
        backend: any Backend,
        handle: any BackendSession,
        keeping: SessionKeeping
    ) {
        self.agent = agent
        self.backend = backend
        self.handle = handle
        self.keeping = keeping
    }

    // MARK: - Public
    // Runs work as a piece of a fan-out: it speaks through no session the
    // task around it opened, and knows which names that task holds.
    static func asFanOutPiece<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async throws -> T {
        let around = heldAroundFanOut.union(held.keys)

        return try await $current.withValue(nil) {
            try await $held.withValue([:]) {
                try await $heldAroundFanOut.withValue(around) {
                    try await work()
                }
            }
        }
    }

    // MARK: - Private
}
