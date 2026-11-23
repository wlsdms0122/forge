//
//  AgentServing.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Warp

// The agent session is ambient — `invoke` opens it, `agent` steps inside speak
// through it, and `parallel` children do not inherit it. The provider owns that
// scoping; actions only open sessions and send prompts.
protocol AgentServing: Sendable {
    // A hook of `lifecycle` runs inside the session, before a turn, when its
    // event has happened and no hook has run for it since.
    func withSession(
        _ settings: AgentSessionSettings,
        lifecycle: AgentSessionLifecycle,
        body: @Sendable () async throws -> Warp.Value
    ) async throws -> Warp.Value

    // One turn of the current session. Each agent process the turn runs holds
    // a step slot of `slots`; a hook the turn calls for runs holding none,
    // since its own steps take theirs.
    func send(prompt: String, slots: any StepSlotProviding) async throws -> String

    // Compacts the current session's conversation, holding a step slot of
    // `slots`, and answers whether there was a conversation to compact.
    func compact(slots: any StepSlotProviding) async throws -> Bool
}
