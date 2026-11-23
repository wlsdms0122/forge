//
//  CompactionPolicy.swift
//  Forge
//
//  Created by JSilver on 11/23/26.
//

import Foundation

// When the daemon compacts a kept session an invoke takes up.
enum CompactionPolicy: Sendable, Equatable, Codable {
    // Past the daemon's sizes.
    case automatic
    case none
    // Past this many tokens, in place of the daemon's limit.
    case limit(Int)
    
    // MARK: - Property
    // MARK: - Initializer
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let limit = try? container.decode(Int.self), limit > 0 {
            self = .limit(limit)
        } else if let name = try? container.decode(String.self), name == "auto" {
            self = .automatic
        } else if let name = try? container.decode(String.self), name == "none" {
            self = .none
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "a compaction policy is auto, none or a size in tokens"
            )
        }
    }
    
    // MARK: - Public
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .automatic:
            try container.encode("auto")
        
        case .none:
            try container.encode("none")
        
        case let .limit(limit):
            try container.encode(limit)
        }
    }
    
    // MARK: - Private
}
