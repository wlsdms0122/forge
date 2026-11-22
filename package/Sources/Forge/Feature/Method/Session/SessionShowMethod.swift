//
//  SessionShowMethod.swift
//  Forge
//
//  Created by JSilver on 11/22/26.
//

import Foundation

struct SessionShowMethod: Sendable {
    // MARK: - Property
    let store: SessionStore
    
    // MARK: - Initializer
    init(store: SessionStore) {
        self.store = store
    }
    
    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONValue {
        guard let name = request.params["name"]?.stringValue, !name.isEmpty else {
            throw ProtocolError("session.show: 'name' (string) required")
        }
        
        return ["session": try await store.entry(SessionName(name)).json()]
    }
    
    // MARK: - Private
}
