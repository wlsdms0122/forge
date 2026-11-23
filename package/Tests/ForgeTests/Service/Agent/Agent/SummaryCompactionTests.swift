//
//  SummaryCompactionTests.swift
//  ForgeTests
//
//  Created by JSilver on 11/23/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("SummaryCompaction Tests")
struct SummaryCompactionTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("the prompt that ships is what lib holds")
    func promptIsWhatTheRepositoryHolds() throws {
        // Given
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Agent
            .deletingLastPathComponent()   // Agent
            .deletingLastPathComponent()   // Service
            .deletingLastPathComponent()   // ForgeTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package
            .deletingLastPathComponent()   // the repository
            .appendingPathComponent("lib")
            .appendingPathComponent("Compaction.prompt.md")

        // When
        let written = try String(contentsOf: url, encoding: .utf8)

        // Then
        #expect(
            SummaryCompaction().request == written.trimmingCharacters(in: .newlines),
            "lib/Compaction.prompt.md differs from what ships. Run tool/embed-library.sh"
        )
    }

    @Test(
        "the summary is what the answer holds inside its tags, or all of an answer without them",
        arguments: [
            ("<analysis>\nturn by turn\n</analysis>\n<summary>\n1. Request: ship it\n</summary>\n", "1. Request: ship it"),
            ("  the whole answer\n", "the whole answer")
        ]
    )
    func summaryComesFromTags(answer: String, expected: String) async throws {
        // Given
        let sut = SummaryCompaction()
        var replaced: String?

        // When
        let response = try await sut.compact(
            turn: { _ in BackendResponse(text: answer, contextTokens: 9_000) },
            replace: { summary in replaced = summary }
        )

        // Then
        #expect(replaced == expected)
        #expect(response.isCompacted)
        #expect(response.contextTokens == nil)
    }

    @Test("an answer whose summary is empty leaves the conversation as it was")
    func emptySummaryReplacesNothing() async {
        // Given
        let sut = SummaryCompaction()
        var replaced = false

        // Then
        await #expect(throws: BackendProtocolViolation.self) {
            _ = try await sut.compact(
                turn: { _ in BackendResponse(text: "<summary>\n</summary>") },
                replace: { _ in replaced = true }
            )
        }
        #expect(!replaced)
    }

    // MARK: - Private
}
