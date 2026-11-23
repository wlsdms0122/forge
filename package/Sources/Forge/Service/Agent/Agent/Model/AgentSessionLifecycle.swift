//
//  AgentSessionLifecycle.swift
//  Forge
//
//  Created by JSilver on 11/23/26.
//

import Foundation

// What an invoke runs inside its session when an event of the session's life
// falls due.
struct AgentSessionLifecycle: Sendable {
    typealias Hook = @Sendable () async throws -> Void
    
    // MARK: - Property
    let onSessionStart: Hook?
    let onContextStart: Hook?
    
    // MARK: - Initializer
    init(onSessionStart: Hook? = nil, onContextStart: Hook? = nil) {
        self.onSessionStart = onSessionStart
        self.onContextStart = onContextStart
    }
    
    // MARK: - Public
    func hook(for event: AgentSessionEvent) -> Hook? {
        switch event {
        case .sessionStart:
            onSessionStart
        
        case .contextStart:
            onContextStart
        }
    }
    
    // The lifecycle of an invoke that joins a session an invoke around it
    // holds: its own hooks, and that one's where it brings none.
    func joining(_ outer: AgentSessionLifecycle) -> AgentSessionLifecycle {
        AgentSessionLifecycle(
            onSessionStart: onSessionStart ?? outer.onSessionStart,
            onContextStart: onContextStart ?? outer.onContextStart
        )
    }
    
    // MARK: - Private
}
