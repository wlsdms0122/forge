//
//  StepSlotProviding.swift
//  Forge
//
//  Created by JSilver on 11/22/26.
//

import Foundation

// Where a leaf of work takes one of the daemon's step slots for as long as it runs.
protocol StepSlotProviding: Sendable {
    func withStepSlot<T: Sendable>(_ body: () async throws -> T) async throws -> T
}
