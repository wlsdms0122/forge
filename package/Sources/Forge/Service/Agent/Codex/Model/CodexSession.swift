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
    // Whether the turn in flight is the one a compaction asks for the summary.
    var isSummarizing = false

    // MARK: - Initializer
    init(
        threadIdentifier: String? = nil,
        turnIndex: Int = 0,
        cumulativeUsage: AgentUsage? = nil,
        summary: String? = nil
    ) {
        self.threadIdentifier = threadIdentifier
        self.turnIndex = turnIndex
        self.cumulativeUsage = cumulativeUsage
        self.summary = summary
    }

    // MARK: - Public
    // MARK: - Private
}
