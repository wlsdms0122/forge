//
//  SummaryCompaction.swift
//  Forge
//
//  Created by JSilver on 11/23/26.
//

import Foundation

// Forge's own compaction, which any backend's conversation can take: one
// turn has the conversation summarize itself, and the summary opens the
// conversation that takes its place.
struct SummaryCompaction: Sendable {
    // MARK: - Property
    // The prompt that asks a conversation for its summary.
    let request: String

    // MARK: - Initializer
    init(request: String = CompactionPrompt.text) {
        self.request = request
    }

    // MARK: - Public
    // The summary in the answer to `request`. The prompt asks for it inside
    // `<summary>` tags after the analysis it is drawn from; an answer without
    // them is all summary.
    func summary(in answer: String) throws -> String {
        let summary: String

        if
            let open = answer.range(of: "<summary>"),
            let close = answer.range(of: "</summary>", options: .backwards),
            open.upperBound <= close.lowerBound
        {
            summary = answer[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            summary = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !summary.isEmpty else {
            throw BackendProtocolViolation(
                "the turn that summarizes the conversation answered nothing, so the conversation stays as it was"
            )
        }

        return summary
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
}
