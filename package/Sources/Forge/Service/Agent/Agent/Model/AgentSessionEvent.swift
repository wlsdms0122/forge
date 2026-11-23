//
//  AgentSessionEvent.swift
//  Forge
//
//  Created by JSilver on 11/23/26.
//

import Foundation

// A turn of a session's life that the body of an invoke cannot see, in the
// order the two fall due together.
enum AgentSessionEvent: Sendable, CaseIterable {
    // The backend opened the session: it is new, or the conversation a kept
    // one named was gone.
    case sessionStart
    // The conversation holds none of the context an invoke builds: the
    // session started, or was compacted.
    case contextStart
}
