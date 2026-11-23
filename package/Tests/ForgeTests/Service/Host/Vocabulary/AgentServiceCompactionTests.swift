//
//  AgentServiceCompactionTests.swift
//  ForgeTests
//
//  Created by JSilver on 11/22/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("AgentService Compaction Tests")
struct AgentServiceCompactionTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("liveagent-compaction")
    
    // MARK: - Initializer
    // MARK: - Lifecycle
    // MARK: - Test
    @Test("a kept session past the context limit is compacted as the next invoke takes it up")
    func sessionPastTheLimitIsCompactedAsTheNextInvokeTakesItUp() async throws {
        // Given
        let directory = try temporary.make("limit")
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, directory, contextLimit: 2500)
        let name = try SessionName("kept")
        
        _ = try await sut.withSession(AgentSessionSettings(session: name)) {
            _ = try await sut.send(prompt: "one")
            _ = try await sut.send(prompt: "two")
            
            return .string(try await sut.send(prompt: "three"))
        }
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(session: name)) {
            _ = try await sut.send(prompt: "four")
            
            return .string(try await sut.send(prompt: "five"))
        }
        
        // Then
        let record = try #require(try await SessionStore(directory: directory).record(name))
        
        #expect(reply == .string("…,four,five"))
        #expect(backend.compactions.elements.count == 1)
        #expect(record.compactions == 1)
        #expect(record.turns == 5)
    }
    
    @Test("the turns of one invoke are not compacted apart, however large they grow")
    func turnsOfOneInvokeAreNotCompactedApart() async throws {
        // Given
        let directory = try temporary.make("body")
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, directory, contextLimit: 500)
        let name = try SessionName("kept")
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(session: name)) {
            _ = try await sut.send(prompt: "one")
            _ = try await sut.send(prompt: "two")
            
            return .string(try await sut.send(prompt: "three"))
        }
        
        // Then
        #expect(reply == .string("one,two,three"))
        #expect(backend.compactions.elements.isEmpty)
    }
    
    @Test("a session made with a size of its own is compacted past that one")
    func sessionWithItsOwnLimitIsCompactedPastIt() async throws {
        // Given
        let directory = try temporary.make("own")
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, directory)
        let name = try SessionName("kept")
        
        _ = try await sut.withSession(AgentSessionSettings(session: name, compact: .limit(500))) {
            .string(try await sut.send(prompt: "one"))
        }
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(session: name)) {
            .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("…,two"))
        #expect(backend.compactions.elements.count == 1)
    }
    
    @Test("a session whose cache has expired is compacted past the cold floor")
    func coldSessionPastTheFloorIsCompacted() async throws {
        // Given
        let directory = try temporary.make("cold")
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, directory, coldCompactFloor: 500)
        let settings = AgentSessionSettings(session: try SessionName("kept"))
        
        _ = try await sut.withSession(settings) { .string(try await sut.send(prompt: "one")) }
        try await Self.age(try SessionName("kept"), in: directory, by: 2 * 3600)
        
        // When
        let reply = try await sut.withSession(settings) { .string(try await sut.send(prompt: "two")) }
        
        // Then
        #expect(reply == .string("…,two"))
        #expect(backend.compactions.elements.count == 1)
    }
    
    @Test("a session whose cache still stands is not compacted under the limit")
    func warmSessionUnderTheLimitIsNotCompacted() async throws {
        // Given
        let directory = try temporary.make("warm")
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, directory, coldCompactFloor: 500)
        let settings = AgentSessionSettings(session: try SessionName("kept"))
        
        _ = try await sut.withSession(settings) { .string(try await sut.send(prompt: "one")) }
        try await Self.age(try SessionName("kept"), in: directory, by: 600)
        
        // When
        let reply = try await sut.withSession(settings) { .string(try await sut.send(prompt: "two")) }
        
        // Then
        #expect(reply == .string("one,two"))
        #expect(backend.compactions.elements.isEmpty)
    }
    
    @Test("a backend without a cache has no cold session")
    func backendWithoutACacheHasNoColdSession() async throws {
        // Given
        let directory = try temporary.make("cacheless")
        let backend = TranscriptBackend(cacheLifetime: nil)
        let sut = Self.agent(backend, directory, coldCompactFloor: 500)
        let settings = AgentSessionSettings(session: try SessionName("kept"))
        
        _ = try await sut.withSession(settings) { .string(try await sut.send(prompt: "one")) }
        try await Self.age(try SessionName("kept"), in: directory, by: 2 * 3600)
        
        // When
        _ = try await sut.withSession(settings) { .string(try await sut.send(prompt: "two")) }
        
        // Then
        #expect(backend.compactions.elements.isEmpty)
    }
    
    @Test("a session made with compact none is never compacted, whatever a later invoke asks")
    func sessionMadeWithCompactOffIsNeverCompacted() async throws {
        // Given
        let directory = try temporary.make("off")
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, directory, contextLimit: 500)
        let name = try SessionName("kept")
        
        _ = try await sut.withSession(AgentSessionSettings(session: name, compact: .none)) {
            .string(try await sut.send(prompt: "one"))
        }
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(session: name, compact: .automatic)) {
            .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("one,two"))
        #expect(backend.compactions.elements.isEmpty)
    }
    
    @Test("a session without a name is never compacted by the daemon")
    func unnamedSessionIsNotCompacted() async throws {
        // Given
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, try temporary.make("unnamed"), contextLimit: 500)
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings()) {
            _ = try await sut.send(prompt: "one")
            
            return .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("one,two"))
        #expect(backend.compactions.elements.isEmpty)
    }
    
    @Test("a kept session whose conversation is gone when it is compacted starts a new one")
    func compactionThatFindsTheConversationGoneRenewsTheSession() async throws {
        // Given
        let directory = try temporary.make("lost")
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, directory, contextLimit: 500)
        let name = try SessionName("kept")
        let settings = AgentSessionSettings(session: name)
        
        _ = try await sut.withSession(settings) { .string(try await sut.send(prompt: "one")) }
        backend.forgetAll()
        
        // When
        let reply = try await sut.withSession(settings) { .string(try await sut.send(prompt: "two")) }
        
        // Then
        let record = try #require(try await SessionStore(directory: directory).record(name))
        
        #expect(reply == .string("two"))
        #expect(record.turns == 1)
        #expect(record.compactions == 0)
    }
    
    @Test("a compaction that leaves the conversation as it was fails the turn")
    func compactionThatCutNothingFailsTheTurn() async throws {
        // Given
        let directory = try temporary.make("uncut")
        let backend = TranscriptBackend(compacts: false)
        let sut = Self.agent(backend, directory, contextLimit: 500)
        let name = try SessionName("kept")
        
        _ = try await sut.withSession(AgentSessionSettings(session: name)) {
            .string(try await sut.send(prompt: "one"))
        }
        
        // When / Then
        await #expect(throws: BackendProtocolViolation.self) {
            _ = try await sut.withSession(AgentSessionSettings(session: name)) {
                .string(try await sut.send(prompt: "two"))
            }
        }
        
        let record = try #require(try await SessionStore(directory: directory).record(name))
        
        #expect(record.compactions == 0)
        #expect(record.turns == 1)
    }
    
    @Test("a turn that compacts the conversation is recorded as a compaction")
    func turnThatCompactsIsRecordedAsACompaction() async throws {
        // Given
        let directory = try temporary.make("during")
        let backend = TranscriptBackend(overflowingPrompt: "two")
        let sut = Self.agent(backend, directory)
        let name = try SessionName("kept")
        
        // When
        _ = try await sut.withSession(AgentSessionSettings(session: name)) {
            _ = try await sut.send(prompt: "one")
            
            return .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        let record = try #require(try await SessionStore(directory: directory).record(name))
        
        #expect(backend.compactions.elements.isEmpty)
        #expect(record.compactions == 1)
        #expect(record.turns == 2)
    }
    
    @Test("a compact step compacts a session made with compact none")
    func compactStepCompactsASessionMadeWithCompactOff() async throws {
        // Given
        let directory = try temporary.make("asked")
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, directory)
        let name = try SessionName("kept")
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(session: name, compact: .none)) {
            _ = try await sut.send(prompt: "one")
            
            let isCompacted = try await sut.compact()
            
            return .array([.bool(isCompacted), .string(try await sut.send(prompt: "two"))])
        }
        
        // Then
        let record = try #require(try await SessionStore(directory: directory).record(name))
        
        #expect(reply == .array([.bool(true), .string("…,two")]))
        #expect(record.compactions == 1)
        #expect(record.turns == 2)
    }
    
    @Test("a compact step before the session's first turn compacts nothing")
    func compactStepBeforeTheFirstTurnCompactsNothing() async throws {
        // Given
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, try temporary.make("untouched"))
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings()) { .bool(try await sut.compact()) }
        
        // Then
        #expect(reply == .bool(false))
        #expect(backend.compactions.elements.isEmpty)
    }
    
    @Test("a compact step outside a session is refused")
    func compactStepOutsideASessionIsRefused() async throws {
        // Given
        let sut = Self.agent(TranscriptBackend(), try temporary.make("outside"))
        
        // When / Then
        await #expect(throws: AgentSessionMissing.self) { _ = try await sut.compact() }
    }
    
    @Test("a compact step that finds a kept session's conversation gone starts a new one")
    func compactStepThatFindsTheConversationGoneStartsANewOne() async throws {
        // Given
        let directory = try temporary.make("asked-lost")
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, directory)
        let name = try SessionName("kept")
        let settings = AgentSessionSettings(session: name)
        
        _ = try await sut.withSession(settings) { .string(try await sut.send(prompt: "one")) }
        backend.forgetAll()
        
        // When
        let reply = try await sut.withSession(settings) {
            let isCompacted = try await sut.compact()
            
            return .array([.bool(isCompacted), .string(try await sut.send(prompt: "two"))])
        }
        
        // Then
        #expect(reply == .array([.bool(false), .string("two")]))
    }
    
    // MARK: - Private
    private static func agent(
        _ backend: any Backend,
        _ directory: URL,
        contextLimit: Int = 250_000,
        coldCompactFloor: Int = 80_000
    ) -> AgentService {
        AgentService(
            executor: AgentExecutor(backend: backend),
            sessions: SessionStore(directory: directory),
            limits: ForgeConfig.SessionConfig(contextLimit: contextLimit, coldCompactFloor: coldCompactFloor)
        )
    }
    
    // Moves the session's last use back, as time passing between two invokes does.
    private static func age(_ name: SessionName, in directory: URL, by seconds: TimeInterval) async throws {
        let store = SessionStore(directory: directory)
        var record = try #require(try await store.record(name))
        
        record.usedAt = ISO8601.string(Date().addingTimeInterval(-seconds))
        
        try await store.write(record, for: name)
    }
}
