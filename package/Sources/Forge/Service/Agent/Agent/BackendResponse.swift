//
//  BackendResponse.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct BackendResponse: Sendable, Equatable {
    // MARK: - Property
    let text: String
    let usage: AgentUsage?
    let toolEvents: [ToolEvent]
    let stdoutLength: Int
    let durationMs: Int
    // The conversation's size as the turn ended, where the backend reports it.
    let contextTokens: Int?
    // Whether the backend compacted the conversation during the turn.
    let isCompacted: Bool

    // MARK: - Initializer
    init(
        text: String,
        usage: AgentUsage? = nil,
        toolEvents: [ToolEvent] = [],
        stdoutLength: Int = 0,
        durationMs: Int = 0,
        contextTokens: Int? = nil,
        isCompacted: Bool = false
    ) {
        self.text = text
        self.usage = usage
        self.toolEvents = toolEvents
        self.stdoutLength = stdoutLength
        self.durationMs = durationMs
        self.contextTokens = contextTokens
        self.isCompacted = isCompacted
    }

    // MARK: - Public
    // MARK: - Private
}
