//
//  SingleStepSlot.swift
//  ForgeTests
//
//  Created by JSilver on 11/22/26.
//

import Foundation
@testable import Forge

// One step slot. Work that asks for it while it is taken would wait for
// itself, so it fails instead, and `taken` counts the work that held it.
final class SingleStepSlot: StepSlotProviding, @unchecked Sendable {
    struct Taken: Error {}

    // MARK: - Property
    private let lock = NSLock()
    private var isTaken = false
    private var count = 0

    var taken: Int { lock.withLock { count } }

    // MARK: - Initializer
    // MARK: - Public
    func withStepSlot<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        try lock.withLock {
            guard !isTaken else { throw Taken() }

            isTaken = true
            count += 1
        }
        defer { lock.withLock { isTaken = false } }

        return try await body()
    }

    // MARK: - Private
}
