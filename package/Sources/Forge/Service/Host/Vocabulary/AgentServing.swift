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
    // `setup` builds the session's context: it runs inside the session before
    // a turn of the body whenever the conversation holds none of it yet.
    func withSession(
        _ settings: AgentSessionSettings,
        setup: (@Sendable () async throws -> Void)?,
        body: @Sendable () async throws -> Warp.Value
    ) async throws -> Warp.Value

    // One turn of the current session. Each agent process the turn runs holds
    // a step slot of `slots`; a setup the turn calls for runs holding none,
    // since its own steps take theirs.
    func send(prompt: String, slots: any StepSlotProviding) async throws -> String
}
