//
//  AgentSessionBinding.swift
//  Forge
//
//  Created by JSilver on 11/22/26.
//

import Foundation

// A session as one invoke speaks through it: the session, and what that
// invoke builds its context with.
struct AgentSessionBinding: Sendable {
    // MARK: - Property
    let session: AgentSession
    let setup: (@Sendable () async throws -> Void)?

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
