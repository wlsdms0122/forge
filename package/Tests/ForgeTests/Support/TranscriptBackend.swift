//
//  TranscriptBackend.swift
//  ForgeTests
//
//  Created by JSilver on 11/22/26.
//

import Foundation
@testable import Forge

// A backend that keeps each conversation's prompts under the session's id, the
// way a backend with resumable sessions does. A turn replies with the prompts
// the conversation has seen so far, joined by a comma, and reports a
// conversation of a thousand tokens a prompt. Compacting a conversation leaves
// one entry, "…", in place of its prompts.
final class TranscriptBackend: Backend, @unchecked Sendable {
    final class Session: BackendSession, Sendable {
        // MARK: - Property
        let id: String
        
        // MARK: - Initializer
        init(id: String) {
            self.id = id
        }
        
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    let invocations = OrderedCollector<AgentInvocation>()
    // The ids of the sessions compacted, in order.
    let compactions = OrderedCollector<String>()
    let cacheLifetime: Duration?
    // The prompt whose turn the backend compacts its conversation during.
    let overflowingPrompt: String?
    // Whether a compaction this backend is asked for cuts the conversation.
    let compacts: Bool
    
    private let lock = NSLock()
    private var transcripts: [String: [String]] = [:]
    private var opened: Set<String> = []
    
    // MARK: - Initializer
    init(
        cacheLifetime: Duration? = .seconds(3600),
        overflowingPrompt: String? = nil,
        compacts: Bool = true
    ) {
        self.cacheLifetime = cacheLifetime
        self.overflowingPrompt = overflowingPrompt
        self.compacts = compacts
    }
    
    // MARK: - Public
    func invoke(_ invocation: AgentInvocation) async throws -> BackendResponse {
        guard let session = invocation.session as? Session else {
            throw BackendProtocolViolation("a turn came without a transcript session")
        }
        
        invocations.append(invocation)
        
        let prompts = try lock.withLock {
            // A session this backend did not just open names a conversation it must still have.
            guard opened.contains(session.id) || transcripts[session.id] != nil else {
                throw BackendSessionLost(
                    "no conversation for \(session.id)",
                    exit: BackendNonzeroExit("transcript exit 1", exitCode: 1)
                )
            }
            
            transcripts[session.id, default: []].append(invocation.prompt)
            
            return transcripts[session.id] ?? []
        }
        
        return BackendResponse(
            text: prompts.joined(separator: ","),
            durationMs: 1,
            contextTokens: prompts.count * 1000,
            isCompacted: invocation.prompt == overflowingPrompt
        )
    }
    
    func openSession() -> any BackendSession {
        let session = Session(id: UUID().uuidString)
        
        lock.withLock { _ = opened.insert(session.id) }
        
        return session
    }
    
    func record(of session: any BackendSession) throws -> JSONValue {
        guard let session = session as? Session else {
            throw BackendSessionNotKept("the session is not a transcript session")
        }
        
        return ["id": .string(session.id)]
    }
    
    func session(from record: JSONValue) throws -> any BackendSession {
        guard let id = record["id"]?.stringValue else {
            throw BackendSessionNotKept("the record does not name a transcript session")
        }
        
        return Session(id: id)
    }
    
    func compact(
        _ session: any BackendSession,
        turn: @Sendable (String) async throws -> BackendResponse
    ) async throws -> BackendResponse {
        guard let session = session as? Session else {
            throw BackendCompactionUnavailable("the session is not a transcript session")
        }
        
        try lock.withLock {
            guard transcripts[session.id] != nil else {
                throw BackendSessionLost(
                    "no conversation for \(session.id)",
                    exit: BackendNonzeroExit("transcript exit 1", exitCode: 1)
                )
            }
            
            if compacts { transcripts[session.id] = ["…"] }
        }
        
        compactions.append(session.id)
        
        return BackendResponse(text: "", durationMs: 1, isCompacted: compacts)
    }
    
    // Drops every conversation, as a backend whose own storage was cleared.
    func forgetAll() {
        lock.withLock {
            transcripts = [:]
            opened = []
        }
    }
    
    // MARK: - Private
}
