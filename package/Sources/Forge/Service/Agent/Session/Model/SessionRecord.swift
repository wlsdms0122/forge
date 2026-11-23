//
//  SessionRecord.swift
//  Forge
//
//  Created by JSilver on 11/22/26.
//

import Foundation

// What the daemon keeps of a named session between invokes. The conversation
// itself is the backend's; `handle` is how the backend finds it again.
struct SessionRecord: Sendable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
        case provider
        case handle
        case model
        case allowed
        case permissionMode = "permission_mode"
        case createdAt = "created_at"
        case usedAt = "used_at"
        case turns
        case contextTokens = "context_tokens"
        case compact
        case compactions
        case needsSessionStart = "needs_session_start"
        case needsContextStart = "needs_context_start"
    }
    
    // MARK: - Property
    let provider: String
    var handle: JSONValue
    let model: String?
    let allowed: [JSONValue]?
    let permissionMode: String?
    let createdAt: String
    var usedAt: String
    var turns: Int
    // The conversation's size as its last turn ended; nil until a turn reports one.
    var contextTokens: Int?
    // When the daemon compacts the session an invoke takes up.
    let compact: CompactionPolicy
    // How many times the daemon has compacted the conversation.
    var compactions: Int
    // Whether the session started and no invoke's `on_session_start` has run since.
    var needsSessionStart: Bool
    // Whether the conversation holds no context an `on_context_start` built.
    var needsContextStart: Bool
    
    // The events no invoke's hook has run for yet.
    var due: Set<AgentSessionEvent> {
        get {
            var due: Set<AgentSessionEvent> = []
            
            if needsSessionStart { due.insert(.sessionStart) }
            if needsContextStart { due.insert(.contextStart) }
            
            return due
        }
        set {
            needsSessionStart = newValue.contains(.sessionStart)
            needsContextStart = newValue.contains(.contextStart)
        }
    }
    
    // MARK: - Initializer
    init(
        provider: String,
        handle: JSONValue,
        model: String?,
        allowed: [JSONValue]?,
        permissionMode: String?,
        createdAt: String,
        usedAt: String,
        turns: Int,
        contextTokens: Int? = nil,
        compact: CompactionPolicy,
        compactions: Int = 0,
        needsSessionStart: Bool = true,
        needsContextStart: Bool = true
    ) {
        self.provider = provider
        self.handle = handle
        self.model = model
        self.allowed = allowed
        self.permissionMode = permissionMode
        self.createdAt = createdAt
        self.usedAt = usedAt
        self.turns = turns
        self.contextTokens = contextTokens
        self.compact = compact
        self.compactions = compactions
        self.needsSessionStart = needsSessionStart
        self.needsContextStart = needsContextStart
    }
    
    // MARK: - Public
    // The record of the same session starting a new conversation.
    func restarted(handle: JSONValue, at time: String) -> SessionRecord {
        SessionRecord(
            provider: provider,
            handle: handle,
            model: model,
            allowed: allowed,
            permissionMode: permissionMode,
            createdAt: time,
            usedAt: time,
            turns: 0,
            compact: compact
        )
    }
    
    // MARK: - Private
}
