//
//  AgentServiceLifecycleTests.swift
//  ForgeTests
//
//  Created by JSilver on 11/22/26.
//

import Foundation
import Testing
import Warp
@testable import Forge

@Suite("AgentService Lifecycle Tests")
struct AgentServiceLifecycleTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("agentservice-lifecycle")
    
    // MARK: - Initializer
    // MARK: - Lifecycle
    // MARK: - Test
    @Test("the context of a new session starts once, before its first turn")
    func newSessionIsSetUpBeforeItsFirstTurn() async throws {
        // Given
        let sut = Self.agent(TranscriptBackend(), try temporary.make("new"))
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(), lifecycle: Self.boot(sut)) {
            _ = try await sut.send(prompt: "one")
            
            return .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("boot,one,two"))
    }
    
    @Test("the context of a kept session that started does not start again")
    func keptSessionIsNotSetUpAgain() async throws {
        // Given
        let directory = try temporary.make("kept")
        let sut = Self.agent(TranscriptBackend(), directory)
        let name = try SessionName("kept")
        let settings = AgentSessionSettings(session: name)
        
        _ = try await sut.withSession(settings, lifecycle: Self.boot(sut)) { .string(try await sut.send(prompt: "one")) }
        
        // When
        let reply = try await sut.withSession(settings, lifecycle: Self.boot(sut)) {
            .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("boot,one,two"))
        #expect(try await SessionStore(directory: directory).record(name)?.needsContextStart == false)
    }
    
    @Test("a session an invoke without a context start hook used stays in need of one")
    func sessionUsedWithoutASetupStaysInNeedOfOne() async throws {
        // Given
        let directory = try temporary.make("later")
        let sut = Self.agent(TranscriptBackend(), directory)
        let name = try SessionName("kept")
        let settings = AgentSessionSettings(session: name)
        
        _ = try await sut.withSession(settings, lifecycle: AgentSessionLifecycle()) { .string(try await sut.send(prompt: "one")) }
        
        let needsContextStart = try await SessionStore(directory: directory).record(name)?.needsContextStart
        
        // When
        let reply = try await sut.withSession(settings, lifecycle: Self.boot(sut)) {
            .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(needsContextStart == true)
        #expect(reply == .string("one,boot,two"))
    }
    
    @Test("the context of a session the daemon compacted starts again before the turn")
    func compactedSessionIsSetUpAgain() async throws {
        // Given
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, try temporary.make("compacted"), contextLimit: 2500)
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(), lifecycle: Self.boot(sut)) {
            _ = try await sut.send(prompt: "one")
            _ = try await sut.send(prompt: "two")
            
            return .string(try await sut.send(prompt: "three"))
        }
        
        // Then
        #expect(reply == .string("…,boot,three"))
    }
    
    @Test("the context of a session compacted during a turn starts again before the next")
    func sessionTheBackendCompactedIsSetUpAgain() async throws {
        // Given
        let sut = Self.agent(TranscriptBackend(overflowingPrompt: "one"), try temporary.make("overflow"))
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(), lifecycle: Self.boot(sut)) {
            _ = try await sut.send(prompt: "one")
            
            return .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("boot,one,boot,two"))
    }
    
    @Test("the context of a kept session that starts a new conversation starts again")
    func renewedSessionIsSetUpAgain() async throws {
        // Given
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, try temporary.make("renewed"))
        let settings = AgentSessionSettings(session: try SessionName("kept"))
        
        _ = try await sut.withSession(settings, lifecycle: Self.boot(sut)) { .string(try await sut.send(prompt: "one")) }
        backend.forgetAll()
        
        // When
        let reply = try await sut.withSession(settings, lifecycle: Self.boot(sut)) {
            .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("boot,two"))
    }
    
    @Test("a context start hook that fails leaves the session in need of one")
    func failedSetupLeavesTheSessionInNeedOfOne() async throws {
        // Given
        let directory = try temporary.make("failed")
        let sut = Self.agent(TranscriptBackend(), directory)
        let name = try SessionName("kept")
        let settings = AgentSessionSettings(session: name)
        
        await #expect(throws: CancellationError.self) {
            _ = try await sut.withSession(
                settings,
                lifecycle: AgentSessionLifecycle(onContextStart: {
                    _ = try await sut.send(prompt: "half")
                    
                    throw CancellationError()
                })
            ) {
                .string(try await sut.send(prompt: "never"))
            }
        }
        
        // When
        let reply = try await sut.withSession(settings, lifecycle: Self.boot(sut)) {
            .string(try await sut.send(prompt: "one"))
        }
        
        // Then
        #expect(reply == .string("half,boot,one"))
    }
    
    @Test("an invoke that joins a session runs the hooks of the invoke that holds it")
    func joiningInvokeInheritsTheSetup() async throws {
        // Given
        let sut = Self.agent(TranscriptBackend(overflowingPrompt: "one"), try temporary.make("joined"))
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(), lifecycle: Self.boot(sut)) {
            _ = try await sut.send(prompt: "one")
            
            return try await sut.withSession(AgentSessionSettings(shareSession: true), lifecycle: AgentSessionLifecycle()) {
                .string(try await sut.send(prompt: "two"))
            }
        }
        
        // Then
        #expect(reply == .string("boot,one,boot,two"))
    }
    
    @Test("an invoke that joins a session with a hook of its own runs that one")
    func joiningInvokeBringsItsOwnSetup() async throws {
        // Given
        let sut = Self.agent(TranscriptBackend(overflowingPrompt: "one"), try temporary.make("own"))
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(), lifecycle: Self.boot(sut)) {
            _ = try await sut.send(prompt: "one")
            
            return try await sut.withSession(
                AgentSessionSettings(shareSession: true),
                lifecycle: AgentSessionLifecycle(onContextStart: { _ = try await sut.send(prompt: "reboot") })
            ) {
                .string(try await sut.send(prompt: "two"))
            }
        }
        
        // Then
        #expect(reply == .string("boot,one,reboot,two"))
    }
    
    @Test("a hook runs holding no step slot, and its turns and a compaction each take one")
    func setupRunsHoldingNoStepSlot() async throws {
        // Given
        let sut = Self.agent(TranscriptBackend(), try temporary.make("slot"), contextLimit: 1500)
        let slots = SingleStepSlot()
        let boot: @Sendable () async throws -> Void = { _ = try await sut.send(prompt: "boot", slots: slots) }
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(), lifecycle: AgentSessionLifecycle(onContextStart: boot)) {
            _ = try await sut.send(prompt: "one", slots: slots)
            
            return .string(try await sut.send(prompt: "two", slots: slots))
        }
        
        // Then
        #expect(reply == .string("…,boot,two"))
        #expect(slots.taken == 5)
    }
    
    @Test("a compaction during a context start hook leaves the session in need of another")
    func compactionDuringASetupLeavesTheSessionInNeedOfAnother() async throws {
        // Given
        let sut = Self.agent(TranscriptBackend(overflowingPrompt: "boot"), try temporary.make("during"))
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(), lifecycle: Self.boot(sut)) {
            _ = try await sut.send(prompt: "one")
            
            return .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("boot,one,boot,two"))
    }
    
    @Test("an invoke that names a session held around another session inherits its hooks")
    func invokeNamingASessionHeldAroundAnotherInheritsItsSetup() async throws {
        // Given
        let sut = Self.agent(TranscriptBackend(), try temporary.make("around"))
        let outer = AgentSessionSettings(session: try SessionName("outer"))
        
        // When
        let reply = try await sut.withSession(outer, lifecycle: Self.boot(sut)) {
            try await sut.withSession(AgentSessionSettings(session: try SessionName("inner")), lifecycle: AgentSessionLifecycle()) {
                try await sut.withSession(outer, lifecycle: AgentSessionLifecycle()) {
                    .string(try await sut.send(prompt: "one"))
                }
            }
        }
        
        // Then
        #expect(reply == .string("boot,one"))
    }
    
    @Test("a context start hook that finds the conversation gone builds its context once, in the new one")
    func setupThatFindsTheConversationGoneRunsOnce() async throws {
        // Given
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, try temporary.make("gone"))
        let settings = AgentSessionSettings(session: try SessionName("kept"))
        
        _ = try await sut.withSession(settings, lifecycle: AgentSessionLifecycle()) { .string(try await sut.send(prompt: "zero")) }
        backend.forgetAll()
        
        // When
        let reply = try await sut.withSession(settings, lifecycle: Self.boot(sut)) {
            _ = try await sut.send(prompt: "one")
            
            return .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("boot,one,two"))
    }
    
    @Test("a hook that ran stays on record when the turn after it fails")
    func finishedSetupStaysOnRecordWhenTheTurnFails() async throws {
        // Given
        let directory = try temporary.make("turnfails")
        let sut = Self.agent(TranscriptBackend(), directory)
        let name = try SessionName("kept")
        let slots = SingleStepSlot()
        
        // When
        await #expect(throws: SingleStepSlot.Taken.self) {
            _ = try await sut.withSession(AgentSessionSettings(session: name), lifecycle: Self.boot(sut)) {
                // The turn asks for a slot already taken, so it fails after its hook ran.
                try await slots.withStepSlot {
                    .string(try await sut.send(prompt: "one", slots: slots))
                }
            }
        }
        
        // Then
        let record = try #require(try await SessionStore(directory: directory).record(name))
        
        #expect(record.turns == 1)
        #expect(record.needsContextStart == false)
    }
    
    @Test("a new session starts once, before its context does")
    func newSessionStartsOnceBeforeItsContext() async throws {
        // Given
        let sut = Self.agent(TranscriptBackend(), try temporary.make("session-start"))
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(), lifecycle: Self.greetAndBoot(sut)) {
            _ = try await sut.send(prompt: "one")
            
            return .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("greet,boot,one,two"))
    }
    
    @Test("a kept session that started does not start again, compacted or not")
    func keptSessionThatStartedDoesNotStartAgain() async throws {
        // Given
        let directory = try temporary.make("session-kept")
        let sut = Self.agent(TranscriptBackend(), directory, contextLimit: 2500)
        let name = try SessionName("kept")
        let settings = AgentSessionSettings(session: name)
        
        _ = try await sut.withSession(settings, lifecycle: Self.greetAndBoot(sut)) {
            .string(try await sut.send(prompt: "one"))
        }
        
        // When
        let reply = try await sut.withSession(settings, lifecycle: Self.greetAndBoot(sut)) {
            .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        let record = try #require(try await SessionStore(directory: directory).record(name))
        
        #expect(reply == .string("…,boot,two"))
        #expect(record.needsSessionStart == false)
        #expect(record.compactions == 1)
    }
    
    @Test("a kept session whose conversation was gone starts again")
    func keptSessionWhoseConversationWasGoneStartsAgain() async throws {
        // Given
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, try temporary.make("session-lost"))
        let settings = AgentSessionSettings(session: try SessionName("kept"))
        
        _ = try await sut.withSession(settings, lifecycle: Self.greetAndBoot(sut)) {
            .string(try await sut.send(prompt: "one"))
        }
        backend.forgetAll()
        
        // When
        let reply = try await sut.withSession(settings, lifecycle: Self.greetAndBoot(sut)) {
            .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("greet,boot,two"))
    }
    
    @Test("a session an invoke without a session start hook used stays in need of one")
    func sessionWithoutASessionStartHookStaysInNeedOfOne() async throws {
        // Given
        let directory = try temporary.make("session-unstarted")
        let sut = Self.agent(TranscriptBackend(), directory)
        let name = try SessionName("kept")
        let settings = AgentSessionSettings(session: name)
        
        _ = try await sut.withSession(settings, lifecycle: Self.boot(sut)) {
            .string(try await sut.send(prompt: "one"))
        }
        
        let needsSessionStart = try await SessionStore(directory: directory).record(name)?.needsSessionStart
        
        // When
        let reply = try await sut.withSession(settings, lifecycle: Self.greetAndBoot(sut)) {
            .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(needsSessionStart == true)
        #expect(reply == .string("boot,one,greet,two"))
    }
    
    @Test("a session start hook that fails leaves the session in need of one")
    func sessionStartHookThatFailsLeavesTheSessionInNeedOfOne() async throws {
        // Given
        let directory = try temporary.make("session-failed")
        let sut = Self.agent(TranscriptBackend(), directory)
        let name = try SessionName("kept")
        let settings = AgentSessionSettings(session: name)
        
        await #expect(throws: CancellationError.self) {
            _ = try await sut.withSession(
                settings,
                lifecycle: AgentSessionLifecycle(onSessionStart: {
                    _ = try await sut.send(prompt: "half")
                    
                    throw CancellationError()
                })
            ) {
                .string(try await sut.send(prompt: "never"))
            }
        }
        
        // When
        let record = try #require(try await SessionStore(directory: directory).record(name))
        
        // Then
        #expect(record.needsSessionStart)
        #expect(record.needsContextStart)
        #expect(record.turns == 1)
    }
    
    // MARK: - Private
    private static func agent(
        _ backend: any Backend,
        _ directory: URL,
        contextLimit: Int = 250_000
    ) -> AgentService {
        AgentService(
            executor: AgentExecutor(backend: backend),
            sessions: SessionStore(directory: directory),
            limits: ForgeConfig.SessionConfig(contextLimit: contextLimit)
        )
    }
    
    // A lifecycle whose session start and context start are one turn each.
    private static func greetAndBoot(_ agent: AgentService) -> AgentSessionLifecycle {
        AgentSessionLifecycle(
            onSessionStart: { _ = try await agent.send(prompt: "greet") },
            onContextStart: { _ = try await agent.send(prompt: "boot") }
        )
    }
    
    // A lifecycle whose context start is one turn.
    private static func boot(_ agent: AgentService) -> AgentSessionLifecycle {
        AgentSessionLifecycle(onContextStart: { _ = try await agent.send(prompt: "boot") })
    }
}
