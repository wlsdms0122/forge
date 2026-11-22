//
//  SessionStoreError.swift
//  Forge
//
//  Created by JSilver on 11/22/26.
//

import Foundation

enum SessionStoreError: ForgeError {
    case invalidName(String)
    case notFound(String)
    case unreadable(String, reason: String)
    case held(String)
    
    var message: String {
        switch self {
        case let .invalidName(name):
            "session name must be path components of [A-Za-z0-9._-] with no leading dot"
                + " and no trailing '.json', joined by '/': '\(name)'"
        
        case let .notFound(name):
            "session not found: \(name)"
        
        case let .unreadable(name, reason):
            "session record present but unreadable: \(name) (\(reason));"
                + " `forge session delete \(name)` starts it over"
        
        case let .held(name):
            "session is held by a running invoke: \(name)"
        }
    }
}
