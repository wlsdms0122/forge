//
//  FreeStepSlot.swift
//  ForgeTests
//
//  Created by JSilver on 11/22/26.
//

import Foundation
@testable import Forge

// Step slots without a limit: the work runs at once.
struct FreeStepSlot: StepSlotProviding {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func withStepSlot<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        try await body()
    }

    // MARK: - Private
}
