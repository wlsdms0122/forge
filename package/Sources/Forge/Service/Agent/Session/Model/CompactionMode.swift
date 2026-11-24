//
//  CompactionMode.swift
//  Forge
//
//  Created by JSilver on 11/24/26.
//

import Foundation

// Whose compaction shrinks a session's conversation.
enum CompactionMode: String, Sendable, Equatable, Codable {
    // The provider's own where it has one, Forge's where it has none.
    case automatic = "auto"
    // The provider's own.
    case provider
    // Forge's: the conversation summarizes itself, and the summary opens the
    // conversation that takes its place.
    case builtin
}
