//
//  BackendSessionNotKept.swift
//  Forge
//
//  Created by JSilver on 11/22/26.
//

import Foundation

struct BackendSessionNotKept: ForgeError {
    // MARK: - Property
    let message: String
    
    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }
    
    // MARK: - Public
    // MARK: - Private
}
