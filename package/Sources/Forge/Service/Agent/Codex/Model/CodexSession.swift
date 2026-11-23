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
    // What a compaction left of the thread it dropped; the next turn opens
    // the new thread with it.
    var summary: String?
    // The file codex writes the thread's events to, once a turn has found it.
    var rolloutPath: String?
    // Whether the turn in flight is the one a compaction asks for the summary.
    var isSummarizing = false

    // MARK: - Initializer
    init(
        threadIdentifier: String? = nil,
        turnIndex: Int = 0,
        cumulativeUsage: AgentUsage? = nil,
        summary: String? = nil,
        rolloutPath: String? = nil
    ) {
        self.threadIdentifier = threadIdentifier
        self.turnIndex = turnIndex
        self.cumulativeUsage = cumulativeUsage
        self.summary = summary
        self.rolloutPath = rolloutPath
    }

    // MARK: - Public
    // MARK: - Private
}
