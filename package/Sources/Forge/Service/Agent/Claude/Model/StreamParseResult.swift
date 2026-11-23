//
//  StreamParseResult.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct StreamParseResult: Sendable, Equatable {
    // MARK: - Property
    var finalText: String
    var toolEvents: [ToolEvent]
    var usage: StreamUsage?
    var malformedLineCount: Int = 0
    var sawTerminalResult: Bool = false
    // What the last request of the turn carried in: the conversation's size as the turn ended.
    var contextTokens: Int?
    // Whether the conversation was compacted during the turn.
    var sawCompaction: Bool = false

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
