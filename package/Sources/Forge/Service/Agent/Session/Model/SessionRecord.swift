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
        case compactMode = "compact_mode"
        case compactions
        case needsSessionStart = "needs_session_start"
        case needsContextStart = "needs_context_start"
        case summary
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
    // Whose compaction shrinks the conversation.
    let compactMode: CompactionMode
    // How many times the daemon has compacted the conversation.
    var compactions: Int
    // Whether the session started and no invoke's `on_session_start` has run since.
    var needsSessionStart: Bool
    // Whether the conversation holds no context an `on_context_start` built.
    var needsContextStart: Bool
    // What Forge's compaction left of the conversation it replaced, until a
    // turn of the one in its place has opened with it.
    var summary: String?
    
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
        compactMode: CompactionMode,
        compactions: Int = 0,
        needsSessionStart: Bool = true,
        needsContextStart: Bool = true,
        summary: String? = nil
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
        self.compactMode = compactMode
        self.compactions = compactions
        self.needsSessionStart = needsSessionStart
        self.needsContextStart = needsContextStart
        self.summary = summary
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        provider = try container.decode(String.self, forKey: .provider)
        handle = try container.decode(JSONValue.self, forKey: .handle)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        allowed = try container.decodeIfPresent([JSONValue].self, forKey: .allowed)
        permissionMode = try container.decodeIfPresent(String.self, forKey: .permissionMode)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        usedAt = try container.decode(String.self, forKey: .usedAt)
        turns = try container.decode(Int.self, forKey: .turns)
        contextTokens = try container.decodeIfPresent(Int.self, forKey: .contextTokens)
        compact = try container.decode(CompactionPolicy.self, forKey: .compact)
        // A record that names no mode is of a session that chose none.
        compactMode = try container.decodeIfPresent(CompactionMode.self, forKey: .compactMode) ?? .automatic
        compactions = try container.decode(Int.self, forKey: .compactions)
        needsSessionStart = try container.decode(Bool.self, forKey: .needsSessionStart)
        needsContextStart = try container.decode(Bool.self, forKey: .needsContextStart)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
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
            compact: compact,
            compactMode: compactMode
        )
    }
    
    // MARK: - Private
}
