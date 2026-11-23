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

    @Test("a compaction drops the thread and the next turn opens a new one with the summary")
    func compactionCarriesSummaryIntoNewThread() async throws {
        // Given
        let codex = try FakeCodex()
        defer { codex.remove() }
        let sut = CodexBackend(executable: codex.executable.path)
        let session = sut.openSession()
        let compaction = SummaryCompaction()
        _ = try await sut.invoke(invocation("first", in: session, at: codex.directory))

        // When
        let response = try await sut.compact(session) { prompt in
            try await sut.invoke(invocation(prompt, in: session, at: codex.directory))
        }
        let kept = try sut.session(from: try sut.record(of: session))
        _ = try await sut.invoke(invocation("later", in: kept, at: codex.directory))
        _ = try await sut.invoke(invocation("last", in: kept, at: codex.directory))
        let calls = try codex.calls()

        // Then
        #expect(response.isCompacted)
        #expect(response.contextTokens == nil)
        #expect(calls.count == 4)
        #expect(calls[1].arguments.contains("thread-1"))
        #expect(calls[1].prompt == compaction.request)
        #expect(calls[1].arguments.contains("model_reasoning_effort=\"low\""))
        #expect(!calls[2].arguments.contains("model_reasoning_effort=\"low\""))
        #expect(!calls[2].arguments.contains("resume"))
        #expect(calls[2].prompt == compaction.opening("later", after: "answer 2"))
        #expect(calls[3].arguments.contains("thread-2"))
        #expect(calls[3].prompt == "last")
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
