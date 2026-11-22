//
//  AgentServing+Testing.swift
//  ForgeTests
//
//  Created by JSilver on 11/22/26.
//

import Foundation
import Warp
@testable import Forge

extension AgentServing {
    // A session whose invoke brings no setup.
    func withSession(
        _ settings: AgentSessionSettings,
        body: @Sendable () async throws -> Warp.Value
    ) async throws -> Warp.Value {
        try await withSession(settings, setup: nil, body: body)
    }

    // A turn outside any pool of step slots.
    func send(prompt: String) async throws -> String {
        try await send(prompt: prompt, slots: FreeStepSlot())
    }
}
