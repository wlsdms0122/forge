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
    
    // MARK: - Initializer
    init(
        provider: String,
        handle: JSONValue,
        model: String?,
        allowed: [JSONValue]?,
        permissionMode: String?,
        createdAt: String,
        usedAt: String,
        turns: Int
    ) {
        self.provider = provider
        self.handle = handle
        self.model = model
        self.allowed = allowed
        self.permissionMode = permissionMode
        self.createdAt = createdAt
        self.usedAt = usedAt
        self.turns = turns
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
            turns: 0
        )
    }
    
    // MARK: - Private
}
