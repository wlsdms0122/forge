//
//  CodexSession.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

final class CodexSession: BackendSession, @unchecked Sendable {
    // MARK: - Property
    var threadIdentifier: String?
    var turnIndex: Int
    var cumulativeUsage: AgentUsage?
    // The file codex writes the thread's events to, once a turn has found it.
    var rolloutPath: String?

    // MARK: - Initializer
    init(
        threadIdentifier: String? = nil,
        turnIndex: Int = 0,
        cumulativeUsage: AgentUsage? = nil,
        rolloutPath: String? = nil
    ) {
        self.threadIdentifier = threadIdentifier
        self.turnIndex = turnIndex
        self.cumulativeUsage = cumulativeUsage
        self.rolloutPath = rolloutPath
    }

    // MARK: - Public
    // MARK: - Private
}
