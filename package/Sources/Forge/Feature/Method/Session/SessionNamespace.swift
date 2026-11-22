//
//  SessionNamespace.swift
//  Forge
//
//  Created by JSilver on 11/22/26.
//

import Foundation

struct SessionNamespace: Sendable {
    // MARK: - Property
    let methods: [RPCMethod]
    
    // MARK: - Initializer
    init(store: SessionStore) {
        let list = SessionListMethod(store: store)
        let show = SessionShowMethod(store: store)
        let delete = SessionDeleteMethod(store: store)
        
        self.methods = [
            RPCMethod("session.list", .unary(.token) { request, _ in
                try await list.handle(request)
            }),
            RPCMethod("session.show", .unary(.token) { request, _ in
                try await show.handle(request)
            }),
            RPCMethod("session.delete", .unary(.token) { request, _ in
                try await delete.handle(request)
            })
        ]
    }
    
    // MARK: - Public
    // MARK: - Private
}
