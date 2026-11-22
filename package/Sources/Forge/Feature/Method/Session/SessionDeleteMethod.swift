//
//  SessionDeleteMethod.swift
//  Forge
//
//  Created by JSilver on 11/22/26.
//

import Foundation

struct SessionDeleteMethod: Sendable {
    // MARK: - Property
    let store: SessionStore
    
    // MARK: - Initializer
    init(store: SessionStore) {
        self.store = store
    }
    
    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONValue {
        guard let name = request.params["name"]?.stringValue, !name.isEmpty else {
            throw ProtocolError("session.delete: 'name' (string) required")
        }
        
        try await store.delete(SessionName(name))
        
        return ["name": .string(name), "deleted": true]
    }
    
    // MARK: - Private
}
