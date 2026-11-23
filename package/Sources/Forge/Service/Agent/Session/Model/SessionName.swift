//
//  SessionName.swift
//  Forge
//
//  Created by JSilver on 11/22/26.
//

import Foundation

// The name of a kept session: path components of [A-Za-z0-9._-] joined by
// '/', held in lowercase. Spellings that differ only in case are one name,
// as they are one path on a volume that ignores case.
struct SessionName: Sendable, Hashable, CustomStringConvertible {
    // MARK: - Property
    // What a record's file ends in. No component ends in it, so no name's
    // record sits where another name's directory would.
    static let recordExtension = "json"
    
    let rawValue: String
    
    var description: String { rawValue }
    
    // MARK: - Initializer
    init(_ text: String) throws {
        let name = text.lowercased()
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        let isSafe = components.allSatisfy { component in
            !component.isEmpty
                && !component.hasPrefix(".")
                && !component.hasSuffix(".\(Self.recordExtension)")
                && component.allSatisfy { character in
                    character.isASCII
                        && (character.isLetter || character.isNumber || character == "." || character == "_" || character == "-")
                }
        }
        
        guard isSafe else { throw SessionStoreError.invalidName(text) }
        
        self.rawValue = name
    }
    
    // MARK: - Public
    // MARK: - Private
}
