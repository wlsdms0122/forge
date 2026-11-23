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
    @Test("a session past the context limit is compacted before its next turn")
    func sessionPastTheLimitIsCompactedBeforeItsNextTurn() async throws {
        // Given
        let directory = try temporary.make("limit")
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, directory, contextLimit: 2500)
        let name = try SessionName("kept")
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(session: name)) {
            _ = try await sut.send(prompt: "one")
            _ = try await sut.send(prompt: "two")
            _ = try await sut.send(prompt: "three")
            
            return .string(try await sut.send(prompt: "four"))
        }
        
        // Then
        let record = try #require(try await SessionStore(directory: directory).record(name))
        
        #expect(reply == .string("…,four"))
        #expect(backend.compactions.elements.count == 1)
        #expect(record.compactions == 1)
        #expect(record.contextTokens == 2000)
        #expect(record.turns == 4)
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
    
    @Test("a session made with compact off is never compacted, whatever a later invoke asks")
    func sessionMadeWithCompactOffIsNeverCompacted() async throws {
        // Given
        let directory = try temporary.make("off")
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, directory, contextLimit: 500)
        let name = try SessionName("kept")
        
        _ = try await sut.withSession(AgentSessionSettings(session: name, compact: false)) {
            .string(try await sut.send(prompt: "one"))
        }
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings(session: name, compact: true)) {
            .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("one,two"))
        #expect(backend.compactions.elements.isEmpty)
    }
    
    @Test("a session without a name is compacted past the limit as a named one is")
    func unnamedSessionIsCompactedPastTheLimit() async throws {
        // Given
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, try temporary.make("unnamed"), contextLimit: 500)
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings()) {
            _ = try await sut.send(prompt: "one")
            
            return .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("…,two"))
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
