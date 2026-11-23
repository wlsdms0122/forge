//
//  CodexSessionRecord.swift
//  Forge
//
//  Created by JSilver on 11/23/26.
//

import Foundation

// What finds a codex session's conversation again in a later process.
struct CodexSessionRecord: Sendable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
        case threadIdentifier = "thread_id"
        case turnIndex = "turn_index"
        case usage
        case summary
        case rolloutPath = "rollout_path"
    }

    // MARK: - Property
    // Nil until a turn starts the thread.
    let threadIdentifier: String?
    let turnIndex: Int
    // What the thread's turns have used in all, which codex reports each turn.
    let usage: AgentUsage?
    let summary: String?
    let rolloutPath: String?

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
