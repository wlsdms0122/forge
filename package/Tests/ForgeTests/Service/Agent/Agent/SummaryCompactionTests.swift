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
    func summaryComesFromTags(answer: String, expected: String) throws {
        // Given
        let sut = SummaryCompaction()

        // When
        let summary = try sut.summary(in: answer)

        // Then
        #expect(summary == expected)
    }

    @Test("an answer that holds no summary is refused")
    func emptySummaryIsRefused() {
        // Given
        let sut = SummaryCompaction()

        // Then
        #expect(throws: BackendProtocolViolation.self) {
            _ = try sut.summary(in: "<summary>\n</summary>")
        }
    }

    // MARK: - Private
}
