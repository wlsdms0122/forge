//
//  SessionEntry.swift
//  Forge
//
//  Created by JSilver on 11/22/26.
//

import Foundation

// A session as the store shows it: its record, and where its line stands.
struct SessionEntry: Sendable, Equatable {
    // MARK: - Property
    let name: SessionName
    let record: SessionRecord
    let isHeld: Bool
    let waiting: Int
    
    // MARK: - Initializer
    // MARK: - Public
    func json() throws -> JSONValue {
        var object = try JSONValue(encoding: record).objectValue ?? [:]
        object["name"] = .string(name.rawValue)
        object["held"] = .bool(isHeld)
        object["waiting"] = .int(waiting)
        
        return .object(object)
    }
    
    // MARK: - Private
}
