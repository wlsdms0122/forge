//
//  SummaryCompaction.swift
//  Forge
//
//  Created by JSilver on 11/23/26.
//

import Foundation

// Compacts a conversation whose backend has no compaction of its own: one
// turn has the conversation summarize itself, and the summary opens the
// conversation that takes its place.
struct SummaryCompaction {
    // MARK: - Property
    // The prompt that asks a conversation for its summary.
    let request = CompactionPrompt.text

    // MARK: - Initializer
    // MARK: - Public
    // Asks the conversation for its summary through `turn` and hands it to
    // `replace`, which puts the new conversation in the old one's place.
    func compact(
        turn: @Sendable (String) async throws -> BackendResponse,
        replace: (String) -> Void
    ) async throws -> BackendResponse {
        let response = try await turn(request)
        let summary = summary(in: response.text)

        guard !summary.isEmpty else {
            throw BackendProtocolViolation(
                "the turn that summarizes the conversation answered nothing, so the conversation stays as it was"
            )
        }

        replace(summary)

        // The size the turn measured is the old conversation's.
        return BackendResponse(
            text: response.text,
            usage: response.usage,
            toolEvents: response.toolEvents,
            stdoutLength: response.stdoutLength,
            durationMs: response.durationMs,
            isCompacted: true
        )
    }

    // The prompt that carries the summary into a conversation that starts empty.
    func opening(_ prompt: String, after summary: String) -> String {
        """
        This conversation continues an earlier one, which this summary replaced.

        <summary>
        \(summary)
        </summary>

        \(prompt)
        """
    }

    // MARK: - Private
    // The prompt asks for the summary inside `<summary>` tags after the
    // analysis it is drawn from; an answer without them is all summary.
    private func summary(in text: String) -> String {
        guard
            let open = text.range(of: "<summary>"),
            let close = text.range(of: "</summary>", options: .backwards),
            open.upperBound <= close.lowerBound
        else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
