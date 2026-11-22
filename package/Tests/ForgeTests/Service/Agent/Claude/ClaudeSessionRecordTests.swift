//
//  ClaudeSessionRecordTests.swift
//  ForgeTests
//
//  Created by JSilver on 11/22/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("ClaudeSessionRecord Tests")
struct ClaudeSessionRecordTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("claude-record")
    
    // MARK: - Initializer
    // MARK: - Test
    @Test("the session a record names resumes the conversation the recorded session spoke in")
    func recordedSessionResumes() throws {
        // Given
        let sut = ClaudeBackend()
        let spoken = ClaudeSession(sessionID: "S-1", turnIndex: 4, established: true)
        
        // When
        let restored = try #require(try sut.session(from: sut.record(of: spoken)) as? ClaudeSession)
        
        // Then
        #expect(restored.sessionID == "S-1")
        #expect(restored.turnIndex == 4)
        #expect(restored.established)
    }
    
    @Test("a record that names no claude session is refused")
    func foreignRecordIsRefused() {
        // Given
        let sut = ClaudeBackend()
        
        // When / Then
        #expect(throws: BackendSessionNotKept.self) {
            _ = try sut.session(from: ["thread": "T-1"])
        }
        #expect(throws: BackendSessionNotKept.self) {
            _ = try sut.record(of: NoSession())
        }
    }
    
    @Test("a resume claude answers with no conversation fails as a lost session")
    func resumeOfAMissingConversationIsLost() async throws {
        // Given
        let executable = try fakeClaude(
            in: try temporary.make("lost"),
            stderr: "No conversation found with session ID: S-GONE"
        )
        let sut = ClaudeBackend(executable: executable.path)
        let session = ClaudeSession(sessionID: "S-GONE", turnIndex: 2, established: true)
        
        // When / Then
        await #expect(throws: BackendSessionLost.self) {
            _ = try await sut.invoke(
                AgentInvocation(id: "t", agent: try Agent(model: "claude:haiku"), prompt: "go", session: session)
            )
        }
    }
    
    @Test("any other failed resume stays a nonzero exit")
    func otherFailedResumeIsANonzeroExit() async throws {
        // Given
        let executable = try fakeClaude(in: try temporary.make("other"), stderr: "rate limited")
        let sut = ClaudeBackend(executable: executable.path)
        let session = ClaudeSession(sessionID: "S-1", turnIndex: 2, established: true)
        
        // When / Then
        await #expect(throws: BackendNonzeroExit.self) {
            _ = try await sut.invoke(
                AgentInvocation(id: "t", agent: try Agent(model: "claude:haiku"), prompt: "go", session: session)
            )
        }
    }
    
    // MARK: - Private
    private func fakeClaude(in directory: URL, stderr: String) throws -> URL {
        let executable = directory.appendingPathComponent("fakeclaude")
        let script = """
        #!/bin/sh
        echo "\(stderr)" >&2
        exit 1
        """
        
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        
        return executable
    }
}
