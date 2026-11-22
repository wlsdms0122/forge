//
//  BackendSessionLost.swift
//  Forge
//
//  Created by JSilver on 11/22/26.
//

import Foundation

// The backend no longer has the conversation the session names.
struct BackendSessionLost: WorkFailure {
    // MARK: - Property
    let message: String
    // How the backend's turn ended, for a caller that does not start the session over.
    let exit: BackendNonzeroExit
    
    // MARK: - Initializer
    init(_ message: String, exit: BackendNonzeroExit) {
        self.message = message
        self.exit = exit
    }
    
    // MARK: - Public
    // MARK: - Private
}
