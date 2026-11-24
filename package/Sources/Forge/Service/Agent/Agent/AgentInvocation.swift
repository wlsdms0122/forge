//
//  AgentInvocation.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct AgentInvocation: Sendable, Equatable {
    // MARK: - Property
    let id: String
    let agent: Agent
    let prompt: String
    let session: (any BackendSession)?
    // Whether the prompt asks the conversation for its summary, which is a
    // reading of what is already there.
    let isSummaryRequest: Bool

    // MARK: - Initializer
    init(
        id: String,
        agent: Agent,
        prompt: String,
        session: (any BackendSession)? = nil,
        isSummaryRequest: Bool = false
    ) {
        self.id = id
        self.agent = agent
        self.prompt = prompt
        self.session = session
        self.isSummaryRequest = isSummaryRequest
    }

    // MARK: - Public
    static func == (left: AgentInvocation, right: AgentInvocation) -> Bool {
        left.id == right.id && left.agent == right.agent && left.prompt == right.prompt
    }

    // MARK: - Private
}
