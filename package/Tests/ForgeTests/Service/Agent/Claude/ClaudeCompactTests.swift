//
//  ClaudeCompactTests.swift
//  ForgeTests
//
//  Created by JSilver on 11/22/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("Claude Compact Tests")
struct ClaudeCompactTests {
    // MARK: - Property
    private static let compacted = """
        {"type":"system","subtype":"status","status":"compacting"}
        {"type":"system","subtype":"compact_boundary","compact_metadata":{"trigger":"manual","pre_tokens":56200,"post_tokens":7000}}
        {"type":"result","subtype":"success","is_error":false,"result":"","usage":{"input_tokens":0,"output_tokens":0}}
        """
    private static let refused = """
        {"type":"result","subtype":"success","is_error":false,"result":"","usage":{"input_tokens":0,"output_tokens":0}}
        """
    
    private let temporary = TemporaryDirectory("claude-compact")
    
    // MARK: - Initializer
    // MARK: - Lifecycle
    // MARK: - Test
    @Test("compact resumes the session's conversation with the compact command")
    func compactResumesTheConversationWithTheCompactCommand() async throws {
        // Given
        let directory = try temporary.make("compact")
        let sut = ClaudeBackend(executable: try fakeClaude(in: directory, frames: Self.compacted).path)
        let session = ClaudeSession(sessionID: "S-1", turnIndex: 3, established: true)
        
        // When
        try await sut.compact(session, agent: try Agent(model: "claude:haiku"))
        
        // Then
        let arguments = try String(contentsOf: directory.appendingPathComponent("arguments"), encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        
        #expect(arguments.contains("/compact"))
        #expect(arguments.firstIndex(of: "--resume").map { index in arguments[index + 1] } == "S-1")
        #expect(session.turnIndex == 3)
    }
    
    @Test("a compact turn that cut nothing fails as a protocol violation")
    func compactTurnWithoutABoundaryFails() async throws {
        // Given
        let sut = ClaudeBackend(executable: try fakeClaude(in: try temporary.make("refused"), frames: Self.refused).path)
        let session = ClaudeSession(sessionID: "S-1", turnIndex: 3, established: true)
        
        // When / Then
        await #expect(throws: BackendProtocolViolation.self) {
            try await sut.compact(session, agent: try Agent(model: "claude:haiku"))
        }
    }
    
    @Test("a conversation claude has not started is left alone")
    func conversationNotStartedIsLeftAlone() async throws {
        // Given
        let directory = try temporary.make("fresh")
        let sut = ClaudeBackend(executable: try fakeClaude(in: directory, frames: Self.refused).path)
        
        // When
        try await sut.compact(ClaudeSession(sessionID: "S-1"), agent: try Agent(model: "claude:haiku"))
        
        // Then
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("arguments").path))
    }
    
    // MARK: - Private
    // A claude that writes its arguments, one a line, beside itself and answers with the frames.
    private func fakeClaude(in directory: URL, frames: String) throws -> URL {
        let executable = directory.appendingPathComponent("fakeclaude")
        let output = directory.appendingPathComponent("frames")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > "\(directory.appendingPathComponent("arguments").path)"
        cat "\(output.path)"
        """
        
        try frames.write(to: output, atomically: true, encoding: .utf8)
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        
        return executable
    }
}
