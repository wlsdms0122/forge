//
//  CodexBackendCompactionTests.swift
//  ForgeTests
//
//  Created by JSilver on 11/23/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("CodexBackendCompaction Tests")
struct CodexBackendCompactionTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("a record brings the thread back for the next turn to resume")
    func recordRestoresThread() async throws {
        // Given
        let codex = try FakeCodex()
        defer { codex.remove() }
        let sut = CodexBackend(executable: codex.executable.path)
        let session = sut.openSession()
        _ = try await sut.invoke(invocation("first", in: session, at: codex.directory))

        // When
        let record = try sut.record(of: session)
        let restored = try sut.session(from: record)
        let response = try await sut.invoke(invocation("second", in: restored, at: codex.directory))
        let calls = try codex.calls()

        // Then
        #expect(record["thread_id"] == "thread-1")
        #expect(record["turn_index"] == 1)
        #expect(calls.count == 2)
        #expect(calls[1].arguments.contains("resume"))
        #expect(calls[1].arguments.contains("thread-1"))
        // Codex counts the thread's turns in all, so the second turn's use is
        // what it added to the first.
        #expect(response.usage?.inputTokens == 10)
    }

    @Test("a session no turn has gone into keeps a record without a thread")
    func recordBeforeFirstTurnHasNoThread() throws {
        // Given
        let sut = CodexBackend(executable: "codex")

        // When
        let restored = try sut.session(from: try sut.record(of: sut.openSession())) as? CodexSession

        // Then
        #expect(restored?.threadIdentifier == nil)
        #expect(restored?.turnIndex == 0)
    }

    @Test("a turn that asks for the conversation's summary reasons low, and no other turn does")
    func summaryRequestReasonsLow() async throws {
        // Given
        let codex = try FakeCodex()
        defer { codex.remove() }
        let sut = CodexBackend(executable: codex.executable.path)
        let session = sut.openSession()
        _ = try await sut.invoke(invocation("first", in: session, at: codex.directory))

        // When
        _ = try await sut.invoke(
            AgentInvocation(
                id: UUID().uuidString,
                agent: try Agent(model: "codex", workingDirectory: codex.directory.path),
                prompt: "summarize",
                session: session,
                isSummaryRequest: true
            )
        )
        let calls = try codex.calls()

        // Then
        #expect(!calls[0].arguments.contains("model_reasoning_effort=\"low\""))
        #expect(calls[1].arguments.contains("model_reasoning_effort=\"low\""))
        #expect(calls[1].arguments.contains("thread-1"))
    }

    @Test("a resume of a thread codex has no record of fails as a lost session")
    func resumeOfAMissingThreadIsLost() async throws {
        // Given
        let codex = try FakeCodex()
        defer { codex.remove() }
        let sut = CodexBackend(executable: codex.executable.path)
        let session = sut.openSession()
        _ = try await sut.invoke(invocation("first", in: session, at: codex.directory))
        try codex.lose("thread-1")

        // When
        let lost = await #expect(throws: BackendSessionLost.self) {
            try await sut.invoke(invocation("second", in: session, at: codex.directory))
        }

        // Then
        #expect(lost?.exit.exitCode == 1)
        #expect(lost?.message.contains("thread-1") == true)
    }

    @Test("a turn reports the size the thread's rollout says its last call was")
    func turnReportsSizeFromRollout() async throws {
        // Given
        let codex = try FakeCodex()
        defer { codex.remove() }
        let sut = CodexBackend(executable: codex.executable.path)
        let session = sut.openSession()
        let agent = try Agent(
            model: "codex",
            workingDirectory: codex.directory.path,
            environment: ["CODEX_HOME": codex.directory.appendingPathComponent("home").path]
        )

        // When
        _ = try await sut.invoke(
            AgentInvocation(id: UUID().uuidString, agent: agent, prompt: "first", session: session)
        )
        let response = try await sut.invoke(
            AgentInvocation(id: UUID().uuidString, agent: agent, prompt: "second", session: session)
        )

        // Then
        #expect(response.contextTokens == 202)
        #expect(try sut.record(of: session)["rollout_path"]?.stringValue?.hasSuffix("-thread-1.jsonl") == true)
    }

    @Test("a turn reads the file its session remembers without a search")
    func turnReadsRememberedRollout() async throws {
        // Given
        let codex = try FakeCodex()
        defer { codex.remove() }
        let sut = CodexBackend(executable: codex.executable.path)
        let remembered = codex.directory.appendingPathComponent("remembered.jsonl")
        try #"{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":900,"output_tokens":7}}}}"#
            .write(to: remembered, atomically: true, encoding: .utf8)
        let session = CodexSession(threadIdentifier: "thread-1", turnIndex: 1, rolloutPath: remembered.path)

        // When
        let response = try await sut.invoke(invocation("next", in: session, at: codex.directory))

        // Then
        #expect(response.contextTokens == 907)
    }

    @Test("a turn whose thread has no rollout reports no size")
    func turnWithoutRolloutReportsNoSize() async throws {
        // Given
        let codex = try FakeCodex()
        defer { codex.remove() }
        let sut = CodexBackend(executable: codex.executable.path)
        let agent = try Agent(
            model: "codex",
            workingDirectory: codex.directory.path,
            environment: ["HOME": codex.directory.path]
        )

        // When
        let response = try await sut.invoke(
            AgentInvocation(id: UUID().uuidString, agent: agent, prompt: "first", session: sut.openSession())
        )

        // Then
        #expect(response.contextTokens == nil)
    }

    // MARK: - Private
    private func invocation(
        _ prompt: String,
        in session: any BackendSession,
        at directory: URL
    ) -> AgentInvocation {
        AgentInvocation(
            id: UUID().uuidString,
            agent: try! Agent(model: "codex", workingDirectory: directory.path),
            prompt: prompt,
            session: session
        )
    }
}
