//
//  AgentLoopBackendSessionTests.swift
//  ForgeTests
//
//  Created by JSilver on 11/23/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("AgentLoopBackendSession Tests")
struct AgentLoopBackendSessionTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("a turn reports the conversation's size from its last round")
    func turnReportsContextTokens() async throws {
        // Given
        let transport = StubChatTransport([
            ChatCompletion(
                text: "answer",
                usage: AgentUsage(inputTokens: 40, outputTokens: 7, cacheReadTokens: 100)
            )
        ])
        let sut = AgentLoopBackend(transport: transport)

        // When
        let response = try await sut.invoke(invocation("go", in: sut.openSession()))

        // Then
        #expect(response.contextTokens == 147)
    }

    @Test("a turn whose endpoint counts nothing reports no size")
    func turnWithoutUsageReportsNoContextTokens() async throws {
        // Given
        let sut = AgentLoopBackend(transport: StubChatTransport([ChatCompletion(text: "answer")]))

        // When
        let response = try await sut.invoke(invocation("go", in: sut.openSession()))

        // Then
        #expect(response.contextTokens == nil)
    }

    @Test("a record brings the conversation back, tool calls included")
    func recordRestoresMessages() throws {
        // Given
        let sut = AgentLoopBackend(transport: StubChatTransport([]))
        let messages = [
            ChatMessage(role: .user, content: "list the files"),
            ChatMessage(
                role: .assistant,
                content: "",
                toolCalls: [ChatToolCall(id: "c1", name: "run_command", arguments: #"{"argv":["ls"]}"#)]
            ),
            ChatMessage(role: .tool, content: "a.txt", toolCallID: "c1"),
            ChatMessage(role: .assistant, content: "one file")
        ]

        // When
        let record = try sut.record(of: AgentLoopSession(messages: messages))
        let restored = try sut.session(from: record) as? AgentLoopSession

        // Then
        #expect(restored?.messages == messages)
    }

    @Test("a record without messages names no session")
    func recordWithoutMessagesIsRefused() {
        // Given
        let sut = AgentLoopBackend(transport: StubChatTransport([]))

        // Then
        #expect(throws: BackendSessionNotKept.self) {
            _ = try sut.session(from: ["thread_id": "t"])
        }
    }

    // MARK: - Private
    private func invocation(_ prompt: String, in session: any BackendSession) -> AgentInvocation {
        AgentInvocation(
            id: UUID().uuidString,
            agent: try! Agent(model: "local:m", allowed: []),
            prompt: prompt,
            session: session
        )
    }
}
