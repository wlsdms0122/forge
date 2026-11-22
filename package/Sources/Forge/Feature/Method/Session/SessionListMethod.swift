//
//  SessionListMethod.swift
//  Forge
//
//  Created by JSilver on 11/22/26.
//

import Foundation

struct SessionListMethod: Sendable {
    // MARK: - Property
    let store: SessionStore
    
    // MARK: - Initializer
    init(store: SessionStore) {
        self.store = store
    }
    
    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONValue {
        let sessions = try await store.all().map { entry in try entry.json() }
        
        return ["sessions": .array(sessions)]
    }
    
    // MARK: - Private
}
