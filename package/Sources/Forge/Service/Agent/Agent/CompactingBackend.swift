//
//  CompactingBackend.swift
//  Forge
//
//  Created by JSilver on 11/24/26.
//

import Foundation

// A backend with a compaction of its own.
protocol CompactingBackend: Backend {
    // Shrinks the session's conversation in place and answers with the turn
    // that did. Each prompt the compaction sends goes through `turn`, as a
    // turn of the session does.
    func compact(
        _ session: any BackendSession,
        turn: @Sendable (String) async throws -> BackendResponse
    ) async throws -> BackendResponse
}
