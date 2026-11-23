//
//  CompactionReason.swift
//  Forge
//
//  Created by JSilver on 11/22/26.
//

import Foundation

// Why a session's conversation was compacted.
enum CompactionReason: String, Sendable {
    // The conversation is past the size any session may reach.
    case limit
    // The backend's cache of the conversation has expired, so the next turn
    // reads all of it at full price.
    case cold
    // A turn of the session compacted it: the backend on its own, or the
    // prompt the turn carried.
    case turn
}
