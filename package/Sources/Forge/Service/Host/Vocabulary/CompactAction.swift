//
//  CompactAction.swift
//  Forge
//
//  Created by JSilver on 11/23/26.
//

import Foundation
import Warp

// A compaction of the agent session `invoke` opened, asked for by the workflow.
struct CompactAction: ForgeAction {
    typealias Parameters = NoParameters

    // MARK: - Property
    static let signature = Signature(
        of: Self.self,
        returns: .bool,
        failing: .these([BackendNonzeroExit.type]),
        isolation: .isolated
    )

    // MARK: - Initializer
    // MARK: - Public
    func act(_ invocation: Invocation<Self>, in environment: ForgeEnvironment) async throws -> Warp.Value {
        .bool(try await environment.capabilities.agent.compact(slots: environment))
    }

    // MARK: - Private
}
