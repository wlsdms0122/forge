//
//  AgentSessionBinding.swift
//  Forge
//
//  Created by JSilver on 11/22/26.
//

import Foundation

// A session as one invoke speaks through it: the session, and what that
// invoke runs at the events of its life.
struct AgentSessionBinding: Sendable {
    // MARK: - Property
    let session: AgentSession
    let lifecycle: AgentSessionLifecycle

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
