//
//  AgentServiceNamedSessionTests.swift
//  ForgeTests
//
//  Created by JSilver on 11/22/26.
//

import Foundation
import Testing
import Warp
@testable import Forge

@Suite("AgentService named session Tests")
struct AgentServiceNamedSessionTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("liveagent-session")
    
    // MARK: - Initializer
    // MARK: - Test
    @Test("a later invoke of a name continues the conversation, over a store and an agent of its own")
    func namedSessionContinuesAcrossInvokes() async throws {
        // Given
        let directory = try temporary.make("continue")
        let backend = TranscriptBackend()
        let settings = AgentSessionSettings(session: try SessionName("review/survey"))
        
        let earlier = Self.agent(backend, directory)
        
        _ = try await earlier.withSession(settings) {
            .string(try await earlier.send(prompt: "first"))
        }
        
        // When
        let sut = Self.agent(backend, directory)
        let reply = try await sut.withSession(settings) {
            .string(try await sut.send(prompt: "second"))
        }
        
        // Then
        let record = try #require(try await SessionStore(directory: directory).record(try SessionName("review/survey")))
        
        #expect(reply == .string("first,second"))
        #expect(record.turns == 2)
        #expect(record.contextTokens == 2000)
    }
    
    @Test("the model, the tools and the permission mode are the session's, and the working directory is each invoke's")
    func sessionSettingsStandOverALaterInvoke() async throws {
        // Given
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, try temporary.make("settings"))
        let first = AgentSessionSettings(
            model: "claude:haiku",
            allowed: [.string("files.read")],
            cwd: "/first",
            permissionMode: "safe",
            session: try SessionName("kept")
        )
        let second = AgentSessionSettings(
            model: "claude:opus",
            cwd: "/second",
            permissionMode: "bypass",
            session: try SessionName("kept")
        )
        
        _ = try await sut.withSession(first) { .string(try await sut.send(prompt: "one")) }
        
        // When
        _ = try await sut.withSession(second) { .string(try await sut.send(prompt: "two")) }
        
        // Then
        let agent = try #require(backend.invocations.elements.last?.agent)
        
        #expect(agent.model?.displayName == "claude:haiku")
        #expect(agent.allowed == [.filesRead])
        #expect(agent.permissionMode == .safe)
        #expect(agent.workingDirectory == "/second")
    }
    
    @Test("two invokes of one name run one after the other")
    func invokesOfOneNameRunInTurn() async throws {
        // Given
        let directory = try temporary.make("turns")
        let backend = TranscriptBackend()
        let store = SessionStore(directory: directory)
        let sut = AgentService(executor: AgentExecutor(backend: backend), sessions: store)
        let settings = AgentSessionSettings(session: try SessionName("shared"))
        let (entered, enteredSignal) = AsyncStream<Void>.makeStream()
        let (leave, leaveSignal) = AsyncStream<Void>.makeStream()
        
        let first = Task {
            try await sut.withSession(settings) {
                let text = try await sut.send(prompt: "a1")
                
                enteredSignal.yield()
                for await _ in leave { break }
                
                return .string(text + "|" + (try await sut.send(prompt: "a2")))
            }
        }
        
        for await _ in entered { break }
        
        // When
        let second = Task {
            try await sut.withSession(settings) {
                .string(try await sut.send(prompt: "b1"))
            }
        }
        
        while try await store.entry(try SessionName("shared")).waiting < 1 { await Task.yield() }
        
        leaveSignal.yield()
        
        // Then
        #expect(try await first.value == .string("a1|a1,a2"))
        #expect(try await second.value == .string("a1,a2,b1"))
        #expect(try await store.entry(try SessionName("shared")).isHeld == false)
    }
    
    @Test("an invoke inside a session of the same name joins it rather than waiting for itself")
    func reenteringAHeldNameJoins() async throws {
        // Given
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, try temporary.make("join"))
        let outer = AgentSessionSettings(session: try SessionName("outer"))
        let other = AgentSessionSettings(session: try SessionName("other"))
        
        // When
        let reply = try await sut.withSession(outer) {
            _ = try await sut.send(prompt: "o1")
            
            return try await sut.withSession(other) {
                try await sut.withSession(outer) {
                    .string(try await sut.send(prompt: "o2"))
                }
            }
        }
        
        // Then
        #expect(reply == .string("o1,o2"))
    }
    
    @Test("a spelling that differs only in case joins the held session, and is refused in a fan-out piece")
    func caseVariantIsTheHeldName() async throws {
        // Given
        let sut = Self.agent(TranscriptBackend(), try temporary.make("case"))
        let outer = AgentSessionSettings(session: try SessionName("Review/Survey"))
        let inner = AgentSessionSettings(session: try SessionName("review/survey"))
        
        // When
        let reply = try await sut.withSession(outer) {
            _ = try await sut.send(prompt: "o1")
            
            return try await sut.withSession(inner) { .string(try await sut.send(prompt: "o2")) }
        }
        
        // Then
        #expect(reply == .string("o1,o2"))
        await #expect(throws: RunRefused.self) {
            _ = try await sut.withSession(outer) {
                try await AgentSession.asFanOutPiece {
                    try await sut.withSession(inner) { .null }
                }
            }
        }
    }
    
    @Test("a name whose conversation the backend lost starts a new one under the same name")
    func lostConversationStartsOver() async throws {
        // Given
        let directory = try temporary.make("lost")
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, directory)
        let settings = AgentSessionSettings(model: "claude:haiku", session: try SessionName("kept"))
        
        _ = try await sut.withSession(settings) { .string(try await sut.send(prompt: "before")) }
        
        let before = try #require(try await SessionStore(directory: directory).record(try SessionName("kept")))
        
        backend.forgetAll()
        
        // When
        let reply = try await sut.withSession(settings) {
            .string(try await sut.send(prompt: "after"))
        }
        
        // Then
        let after = try #require(try await SessionStore(directory: directory).record(try SessionName("kept")))
        
        #expect(reply == .string("after"))
        #expect(after.turns == 1)
        #expect(after.handle != before.handle)
        #expect(after.model == "claude:haiku")
    }
    
    @Test("a conversation lost after a turn of this invoke fails the turn as a nonzero exit")
    func conversationLostMidInvokeFails() async throws {
        // Given
        let directory = try temporary.make("midlost")
        let backend = TranscriptBackend()
        let sut = Self.agent(backend, directory)
        
        // When / Then
        await #expect(throws: BackendNonzeroExit.self) {
            _ = try await sut.withSession(AgentSessionSettings(session: try SessionName("kept"))) {
                _ = try await sut.send(prompt: "one")
                
                backend.forgetAll()
                
                return .string(try await sut.send(prompt: "two"))
            }
        }
        #expect(try await SessionStore(directory: directory).record(try SessionName("kept"))?.turns == 1)
    }
    
    @Test("a piece of a fan-out that names a session held around the fan-out is refused rather than left waiting")
    func fanOutPieceCannotEnterASessionHeldAroundIt() async throws {
        // Given
        let store = SessionStore(directory: try temporary.make("fanout"))
        let sut = AgentService(executor: AgentExecutor(backend: TranscriptBackend()), sessions: store)
        let settings = AgentSessionSettings(session: try SessionName("outer"))
        // When / Then
        await #expect(throws: RunRefused.self) {
            _ = try await sut.withSession(settings) {
                try await AgentSession.asFanOutPiece {
                    try await sut.withSession(settings) { .null }
                }
            }
        }
        
        try await store.acquire(try SessionName("outer"))
        await store.release(try SessionName("outer"))
    }
    
    @Test("a session made without a model stays on its backend when another is registered later")
    func modelLessSessionStaysOnItsBackend() async throws {
        // Given
        let directory = try temporary.make("pinned")
        let backend = TranscriptBackend()
        let settings = AgentSessionSettings(session: try SessionName("kept"))
        let earlier = Self.agent(backend, directory)
        
        _ = try await earlier.withSession(settings) { .string(try await earlier.send(prompt: "one")) }
        
        // When
        let sut = AgentService(
            executor: AgentExecutor(backends: BackendRegistry(["claude": backend, "codex": StubBackend()])),
            sessions: SessionStore(directory: directory)
        )
        let reply = try await sut.withSession(settings) { .string(try await sut.send(prompt: "two")) }
        
        // Then
        #expect(reply == .string("one,two"))
    }
    
    @Test("a session without a name leaves no record")
    func unnamedSessionLeavesNoRecord() async throws {
        // Given
        let directory = try temporary.make("unnamed")
        let sut = Self.agent(TranscriptBackend(), directory)
        
        // When
        let reply = try await sut.withSession(AgentSessionSettings()) {
            _ = try await sut.send(prompt: "one")
            
            return .string(try await sut.send(prompt: "two"))
        }
        
        // Then
        #expect(reply == .string("one,two"))
        #expect(await SessionStore(directory: directory).all().isEmpty)
    }
    
    @Test("a named session on a backend that keeps none is refused before a turn, and the name is let go")
    func backendThatKeepsNoSessionRefusesAName() async throws {
        // Given
        let store = SessionStore(directory: try temporary.make("notkept"))
        let recorder = AgentRecorder()
        let sut = AgentService(executor: AgentExecutor(backend: recorder), sessions: store)
        
        // When
        await #expect(throws: BackendSessionNotKept.self) {
            _ = try await sut.withSession(AgentSessionSettings(session: try SessionName("kept"))) {
                .string(try await sut.send(prompt: "never"))
            }
        }
        
        // Then
        #expect(recorder.invocations.elements.isEmpty)
        
        try await store.acquire(try SessionName("kept"))
        await store.release(try SessionName("kept"))
    }
    
    @Test("a named session no turn finished in keeps no record")
    func sessionWithoutAFinishedTurnKeepsNoRecord() async throws {
        // Given
        let directory = try temporary.make("failed")
        let sut = Self.agent(TranscriptBackend(), directory)
        
        // When
        await #expect(throws: CancellationError.self) {
            _ = try await sut.withSession(AgentSessionSettings(session: try SessionName("kept"))) {
                throw CancellationError()
            }
        }
        
        // Then
        #expect(await SessionStore(directory: directory).all().isEmpty)
    }
    
    // MARK: - Private
    private static func agent(_ backend: any Backend, _ directory: URL) -> AgentService {
        AgentService(executor: AgentExecutor(backend: backend), sessions: SessionStore(directory: directory))
    }
}
