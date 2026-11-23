//
//  AgentExecutor.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct AgentExecutor: Sendable {
    // MARK: - Property
    let backends: BackendRegistry
    let preHooks: [any PreHook]
    let postHooks: [any PostHook]
    let errorHooks: [any ErrorHook]
    
    // MARK: - Initializer
    init(
        backends: BackendRegistry,
        preHooks: [any PreHook] = [],
        postHooks: [any PostHook] = [],
        errorHooks: [any ErrorHook] = []
    ) {
        self.backends = backends
        self.preHooks = preHooks
        self.postHooks = postHooks
        self.errorHooks = errorHooks
    }
    
    // MARK: - Public
    func run(_ invocation: AgentInvocation) async throws -> AgentInvocationResult {
        let started = ContinuousClock.now
        let response = try await respond(to: invocation)
        
        return AgentInvocationResult(response, durationMs: (ContinuousClock.now - started).milliseconds)
    }
    
    // Compacts the session's conversation on the agent's backend. The turns
    // the compaction takes are invocations like any other.
    func compact(_ session: any BackendSession, agent: Agent) async throws -> AgentInvocationResult {
        let started = ContinuousClock.now
        let backend = try backends.resolve(provider: agent.provider)
        let response = try await backend.compact(session) { prompt in
            try await respond(
                to: AgentInvocation(id: UUID().uuidString, agent: agent, prompt: prompt, session: session)
            )
        }
        
        return AgentInvocationResult(response, durationMs: (ContinuousClock.now - started).milliseconds)
    }
    
    // MARK: - Private
    private func respond(to original: AgentInvocation) async throws -> BackendResponse {
        var invocation = original
        
        do {
            for hook in preHooks {
                invocation = try await hook.before(invocation)
            }
            
            let backend = try backends.resolve(provider: invocation.agent.provider)
            let response = try await backend.invoke(invocation)
            
            for hook in postHooks {
                await hook.after(invocation, response)
            }
            
            return response
        } catch {
            for hook in errorHooks {
                let action = await hook.onError(invocation, error)
                
                switch action {
                case .propagate:
                    continue
                
                case .substitute(let response):
                    for postHook in postHooks {
                        await postHook.after(invocation, response)
                    }
                    
                    return response
                }
            }
            
            throw error
        }
    }
}
