//
//  AgentInvocationResult.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct AgentInvocationResult: Sendable, Equatable {
    // MARK: - Property
    let text: String
    let usage: AgentUsage?
    let toolEvents: [ToolEvent]
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
        durationMs: Int,
        contextTokens: Int? = nil,
        isCompacted: Bool = false
    ) {
        self.text = text
        self.usage = usage
        self.toolEvents = toolEvents
        self.durationMs = durationMs
        self.contextTokens = contextTokens
        self.isCompacted = isCompacted
    }

    init(_ response: BackendResponse, durationMs: Int) {
        self.init(
            text: response.text,
            usage: response.usage,
            toolEvents: response.toolEvents,
            durationMs: durationMs,
            contextTokens: response.contextTokens,
            isCompacted: response.isCompacted
        )
    }

    // MARK: - Public
    // MARK: - Private
}
