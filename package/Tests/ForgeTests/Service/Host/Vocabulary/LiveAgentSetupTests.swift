//
//  LiveAgentSetupTests.swift
//  ForgeTests
//
//  Created by JSilver on 11/22/26.
//

import Foundation
import Testing
import Warp
@testable import Forge

@Suite("LiveAgent Setup Tests")
struct LiveAgentSetupTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("liveagent-setup")
    
    // MARK: - Initializer
    // MARK: - Lifecycle
    // MARK: - Test
    @Test("a new session is set up once, before its first turn")
    func newSessionIsSetUpBeforeItsFirstTurn() async throws {
        // Given
        let sut = Self.agent(TranscriptBackend(), try temporary.make("new"))
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(), setup: Self.boot(sut)) {
            _ = try await sut.send(prompt: "one")
            
            return .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("boot,one,two"))
    }
    
    @Test("a kept session that was set up is not set up again")
    func keptSessionIsNotSetUpAgain() async throws {
        // Given
        let directory = try temporary.make("kept")
        let sut = Self.agent(TranscriptBackend(), directory)
        let name = try SessionName("kept")
        let settings = AgentSessionSettings(session: name)
        
        _ = try await sut.withSession(settings, setup: Self.boot(sut)) { .string(try await sut.send(prompt: "one")) }
        
        // When
        let reply = try await sut.withSession(settings, setup: Self.boot(sut)) {
            .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("boot,one,two"))
        #expect(try await SessionStore(directory: directory).record(name)?.needsSetup == false)
    }
    
    @Test("a session an invoke without a setup used stays in need of one")
    func sessionUsedWithoutASetupStaysInNeedOfOne() async throws {
        // Given
        let directory = try temporary.make("later")
        let sut = Self.agent(TranscriptBackend(), directory)
        let name = try SessionName("kept")
        let settings = AgentSessionSettings(session: name)
        
        _ = try await sut.withSession(settings, setup: nil) { .string(try await sut.send(prompt: "one")) }
        
        let needsSetup = try await SessionStore(directory: directory).record(name)?.needsSetup
        
        // When
        let reply = try await sut.withSession(settings, setup: Self.boot(sut)) {
            .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(needsSetup == true)
        #expect(reply == .string("one,boot,two"))
    }
    
    @Test("a session the daemon compacted is set up again before the turn")
    func compactedSessionIsSetUpAgain() async throws {
        // Given
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, try temporary.make("compacted"), contextLimit: 2500)
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(), setup: Self.boot(sut)) {
            _ = try await sut.send(prompt: "one")
            _ = try await sut.send(prompt: "two")
            
            return .string(try await sut.send(prompt: "three"))
        }
        
        // Then
        #expect(reply == .string("…,boot,three"))
    }
    
    @Test("a session its backend compacted during a turn is set up again before the next")
    func sessionTheBackendCompactedIsSetUpAgain() async throws {
        // Given
        let sut = Self.agent(TranscriptBackend(overflowingPrompt: "one"), try temporary.make("overflow"))
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(), setup: Self.boot(sut)) {
            _ = try await sut.send(prompt: "one")
            
            return .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("boot,one,boot,two"))
    }
    
    @Test("a kept session that starts a new conversation is set up again")
    func renewedSessionIsSetUpAgain() async throws {
        // Given
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, try temporary.make("renewed"))
        let settings = AgentSessionSettings(session: try SessionName("kept"))
        
        _ = try await sut.withSession(settings, setup: Self.boot(sut)) { .string(try await sut.send(prompt: "one")) }
        backend.forgetAll()
        
        // When
        let reply = try await sut.withSession(settings, setup: Self.boot(sut)) {
            .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("boot,two"))
    }
    
    @Test("a setup that fails leaves the session in need of one")
    func failedSetupLeavesTheSessionInNeedOfOne() async throws {
        // Given
        let directory = try temporary.make("failed")
        let sut = Self.agent(TranscriptBackend(), directory)
        let name = try SessionName("kept")
        let settings = AgentSessionSettings(session: name)
        
        await #expect(throws: CancellationError.self) {
            _ = try await sut.withSession(
                settings,
                setup: {
                    _ = try await sut.send(prompt: "half")
                    
                    throw CancellationError()
                }
            ) {
                .string(try await sut.send(prompt: "never"))
            }
        }
        
        // When
        let reply = try await sut.withSession(settings, setup: Self.boot(sut)) {
            .string(try await sut.send(prompt: "one"))
        }
        
        // Then
        #expect(reply == .string("half,boot,one"))
    }
    
    @Test("an invoke that joins a session sets it up with the setup of the invoke that holds it")
    func joiningInvokeInheritsTheSetup() async throws {
        // Given
        let sut = Self.agent(TranscriptBackend(overflowingPrompt: "one"), try temporary.make("joined"))
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(), setup: Self.boot(sut)) {
            _ = try await sut.send(prompt: "one")
            
            return try await sut.withSession(AgentSessionSettings(shareSession: true), setup: nil) {
                .string(try await sut.send(prompt: "two"))
            }
        }
        
        // Then
        #expect(reply == .string("boot,one,boot,two"))
    }
    
    @Test("an invoke that joins a session with a setup of its own sets it up with that one")
    func joiningInvokeBringsItsOwnSetup() async throws {
        // Given
        let sut = Self.agent(TranscriptBackend(overflowingPrompt: "one"), try temporary.make("own"))
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(), setup: Self.boot(sut)) {
            _ = try await sut.send(prompt: "one")
            
            return try await sut.withSession(
                AgentSessionSettings(shareSession: true),
                setup: { _ = try await sut.send(prompt: "reboot") }
            ) {
                .string(try await sut.send(prompt: "two"))
            }
        }
        
        // Then
        #expect(reply == .string("boot,one,reboot,two"))
    }
    
    @Test("a setup runs holding no step slot, and its turns and a compaction each take one")
    func setupRunsHoldingNoStepSlot() async throws {
        // Given
        let sut = Self.agent(TranscriptBackend(), try temporary.make("slot"), contextLimit: 1500)
        let slots = SingleStepSlot()
        let boot: @Sendable () async throws -> Void = { _ = try await sut.send(prompt: "boot", slots: slots) }
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(), setup: boot) {
            _ = try await sut.send(prompt: "one", slots: slots)
            
            return .string(try await sut.send(prompt: "two", slots: slots))
        }
        
        // Then
        #expect(reply == .string("…,boot,two"))
        #expect(slots.taken == 5)
    }
    
    @Test("a compaction during a setup leaves the session in need of another")
    func compactionDuringASetupLeavesTheSessionInNeedOfAnother() async throws {
        // Given
        let sut = Self.agent(TranscriptBackend(overflowingPrompt: "boot"), try temporary.make("during"))
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(), setup: Self.boot(sut)) {
            _ = try await sut.send(prompt: "one")
            
            return .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("boot,one,boot,two"))
    }
    
    @Test("an invoke that names a session held around another session inherits its setup")
    func invokeNamingASessionHeldAroundAnotherInheritsItsSetup() async throws {
        // Given
        let sut = Self.agent(TranscriptBackend(), try temporary.make("around"))
        let outer = AgentSessionSettings(session: try SessionName("outer"))
        
        // When
        let reply = try await sut.withSession(outer, setup: Self.boot(sut)) {
            try await sut.withSession(AgentSessionSettings(session: try SessionName("inner")), setup: nil) {
                try await sut.withSession(outer, setup: nil) {
                    .string(try await sut.send(prompt: "one"))
                }
            }
        }
        
        // Then
        #expect(reply == .string("boot,one"))
    }
    
    @Test("a setup that finds the conversation gone builds its context once, in the new one")
    func setupThatFindsTheConversationGoneRunsOnce() async throws {
        // Given
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, try temporary.make("gone"))
        let settings = AgentSessionSettings(session: try SessionName("kept"))
        
        _ = try await sut.withSession(settings, setup: nil) { .string(try await sut.send(prompt: "zero")) }
        backend.forgetAll()
        
        // When
        let reply = try await sut.withSession(settings, setup: Self.boot(sut)) {
            _ = try await sut.send(prompt: "one")
            
            return .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("boot,one,two"))
    }
    
    @Test("a setup that ran stays on record when the turn after it fails")
    func finishedSetupStaysOnRecordWhenTheTurnFails() async throws {
        // Given
        let directory = try temporary.make("turnfails")
        let sut = Self.agent(TranscriptBackend(), directory)
        let name = try SessionName("kept")
        let slots = SingleStepSlot()
        
        // When
        await #expect(throws: SingleStepSlot.Taken.self) {
            _ = try await sut.withSession(AgentSessionSettings(session: name), setup: Self.boot(sut)) {
                // The turn asks for a slot already taken, so it fails after its setup ran.
                try await slots.withStepSlot {
                    .string(try await sut.send(prompt: "one", slots: slots))
                }
            }
        }
        
        // Then
        let record = try #require(try await SessionStore(directory: directory).record(name))
        
        #expect(record.turns == 1)
        #expect(record.needsSetup == false)
    }
    
    // MARK: - Private
    private static func agent(
        _ backend: any Backend,
        _ directory: URL,
        contextLimit: Int = 250_000
    ) -> LiveAgent {
        LiveAgent(
            executor: AgentExecutor(backend: backend),
            sessions: SessionStore(directory: directory),
            limits: ForgeConfig.SessionConfig(contextLimit: contextLimit)
        )
    }
    
    // A setup of one turn.
    private static func boot(_ agent: LiveAgent) -> @Sendable () async throws -> Void {
        { _ = try await agent.send(prompt: "boot") }
    }
}
