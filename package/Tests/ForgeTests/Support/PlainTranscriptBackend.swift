//
//  PlainTranscriptBackend.swift
//  ForgeTests
//
//  Created by JSilver on 11/24/26.
//

import Foundation
@testable import Forge

// A transcript backend with no compaction of its own.
struct PlainTranscriptBackend: Backend {
    // MARK: - Property
    let transcript: TranscriptBackend
    
    var cacheLifetime: Duration? { transcript.cacheLifetime }
    
    // MARK: - Initializer
    init(_ transcript: TranscriptBackend = TranscriptBackend()) {
        self.transcript = transcript
    }
    
    // MARK: - Public
    func invoke(_ invocation: AgentInvocation) async throws -> BackendResponse {
        try await transcript.invoke(invocation)
    }
    
    func openSession() -> any BackendSession {
        transcript.openSession()
    }
    
    func record(of session: any BackendSession) throws -> JSONValue {
        try transcript.record(of: session)
    }
    
    func session(from record: JSONValue) throws -> any BackendSession {
        try transcript.session(from: record)
    }
    
    // MARK: - Private
}
