//
//  CodexRolloutTests.swift
//  ForgeTests
//
//  Created by JSilver on 11/23/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("CodexRollout Tests")
struct CodexRolloutTests {
    // MARK: - Property
    private static let thread = "01a20707-d819-75f0-ad2c-3a5ee40d7d1f"
    // Events of codex-cli 0.170.0, with the system prompt and the rate limits cut.
    private static let events = #"""
        {"timestamp":"2026-11-23T06:11:24.958Z","ordinal":0,"type":"session_meta","payload":{"session_id":"01a20707-d819-75f0-ad2c-3a5ee40d7d1f","id":"01a20707-d819-75f0-ad2c-3a5ee40d7d1f","originator":"codex_exec","cli_version":"0.170.0","source":"exec"}}
        {"timestamp":"2026-11-23T06:12:02.222Z","ordinal":42,"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":63985,"cached_input_tokens":42240,"cache_write_input_tokens":0,"output_tokens":64,"reasoning_output_tokens":0,"total_tokens":64049},"last_token_usage":{"input_tokens":21440,"cached_input_tokens":21248,"cache_write_input_tokens":0,"output_tokens":53,"reasoning_output_tokens":0,"total_tokens":21493},"last_usage_includes_reasoning":true,"model_context_window":475000}}}
        {"timestamp":"2026-11-23T06:12:15.400Z","ordinal":48,"type":"token_usage_record","payload":{"thread_id":"01a20707-d819-75f0-ad2c-3a5ee40d7d1f","usage":{"input_tokens":21564,"output_tokens":49,"total_tokens":21613}}}
        {"timestamp":"2026-11-23T06:12:15.426Z","ordinal":49,"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":85549,"cached_input_tokens":63616,"cache_write_input_tokens":0,"output_tokens":113,"reasoning_output_tokens":13,"total_tokens":85662},"last_token_usage":{"input_tokens":21564,"cached_input_tokens":21376,"cache_write_input_tokens":0,"output_tokens":49,"reasoning_output_tokens":13,"total_tokens":21613},"last_usage_includes_reasoning":true,"model_context_window":475000}}}
        {"timestamp":"2026-11-23T06:12:15.430Z","ordinal":50,"type":"event_msg","payload":{"type":"task_complete"}}

        """#

    // MARK: - Initializer
    // MARK: - Test
    @Test("the size is what the thread's last call to the model held and answered")
    func sizeIsLastCall() throws {
        // Given
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        try write(Self.events, to: "2026/11/23/rollout-2026-11-23T15-11-24-\(Self.thread).jsonl", in: home)
        let sut = CodexRollout(home: home)

        // When
        let size = sut.file(of: Self.thread).flatMap(sut.contextTokens(in:))

        // Then
        #expect(size == 21613)
    }

    @Test("a thread whose history was rewound is sized by its newest file")
    func rewoundThreadIsSizedByNewestFile() throws {
        // Given
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        try write(Self.events, to: "2026/11/23/rollout-2026-11-23T15-11-24-\(Self.thread).jsonl", in: home)
        try write(
            #"{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":900,"output_tokens":7}}}}"#,
            to: "2026/11/24/rollout-2026-11-24T09-00-00-\(Self.thread)_01a13d27-de3a-74c3-a838-7bd0d58c0247.jsonl",
            in: home
        )
        let sut = CodexRollout(home: home)

        // When
        let size = sut.file(of: Self.thread).flatMap(sut.contextTokens(in:))

        // Then
        #expect(size == 907)
    }

    @Test("a thread with no file, or a file with no count, has no size")
    func missingCountHasNoSize() throws {
        // Given
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        try write(
            #"{"type":"session_meta","payload":{"id":"thread-a"}}"#,
            to: "2026/11/23/rollout-2026-11-23T15-11-24-thread-a.jsonl",
            in: home
        )
        let sut = CodexRollout(home: home)

        // When
        let counted = sut.file(of: "thread-a").flatMap(sut.contextTokens(in:))
        let found = sut.file(of: "thread-b").flatMap(sut.contextTokens(in:))

        // Then
        #expect(counted == nil)
        #expect(found == nil)
    }

    @Test("the home is CODEX_HOME, or .codex under HOME where it is unset")
    func homeFollowsEnvironment() {
        // Given
        let named = ["CODEX_HOME": "/tmp/codex-home", "HOME": "/tmp/user"]
        let unnamed = ["HOME": "/tmp/user"]

        // When
        let sut = (CodexRollout(environment: named), CodexRollout(environment: unnamed))

        // Then
        #expect(sut.0.home.path == "/tmp/codex-home")
        #expect(sut.1.home.path == "/tmp/user/.codex")
    }

    // MARK: - Private
    private func home() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-rollout-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        return home
    }

    private func write(_ events: String, to path: String, in home: URL) throws {
        let file = home.appendingPathComponent("sessions").appendingPathComponent(path)

        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try events.write(to: file, atomically: true, encoding: .utf8)
    }
}
