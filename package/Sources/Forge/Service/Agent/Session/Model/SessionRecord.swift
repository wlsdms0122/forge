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
        case needsSetup = "needs_setup"
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
    // Whether the daemon compacts the session as it grows.
    let compact: Bool
    // How many times the daemon has compacted the conversation.
    var compactions: Int
    // Whether the conversation holds no context a setup built.
    var needsSetup: Bool
    
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
        compact: Bool,
        compactions: Int = 0,
        needsSetup: Bool = true
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
        self.needsSetup = needsSetup
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
