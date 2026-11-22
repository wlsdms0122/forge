//
//  BackendRegistry.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct BackendRegistry: Sendable {
    // MARK: - Property
    private let byProvider: [String: any Backend]
    
    // MARK: - Initializer
    init(_ byProvider: [String: any Backend]) {
        self.byProvider = byProvider
    }
    
    // MARK: - Public
    func resolve(provider: String?) throws -> any Backend {
        let name = try name(provider: provider)
        
        guard let backend = byProvider[name] else {
            throw BackendNotRegistered(
                "no backend registered for provider '\(name)' (have: \(byProvider.keys.sorted().joined(separator: ", ")))"
            )
        }
        
        return backend
    }
    
    // The name a provider is registered under; with no provider, the one registered backend's.
    func name(provider: String?) throws -> String {
        guard let provider else {
            guard byProvider.count == 1, let sole = byProvider.keys.first else {
                throw BackendNotRegistered(
                    "a model names no provider, and \(byProvider.count) backends are registered"
                        + " (\(byProvider.keys.sorted().joined(separator: ", "))); name one as"
                        + " `<provider>[:<model>]`"
                )
            }
            
            return sole
        }
        
        return provider
    }
    
    // MARK: - Private
}
