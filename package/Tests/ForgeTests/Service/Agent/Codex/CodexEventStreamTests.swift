//
//  CodexEventStreamTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("CodexEventStream Tests")
struct CodexEventStreamTests {
    private final class CompletedCodexTools: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [(Int, ToolEvent)] = []
        func append(sequence: Int, event: ToolEvent) {
            lock.lock(); defer { lock.unlock() }
            values.append((sequence, event))
        }
        
        var snapshot: [(Int, ToolEvent)] {
            lock.lock(); defer { lock.unlock() }
            
            return values
        }
    }
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("a cache read beyond the input clamps the input at 0")
    func cacheReadBeyondInputClampsAtZero() {
        // Given
        let raw = #"""
        {"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":500}}
        """#

        // When
        let parsed = CodexEventStream.parse(raw)

        // Then
        #expect(parsed.usage == AgentUsage(inputTokens: 0, cacheReadTokens: 500))
    }
    
    @Test("parses thread, message, usage, and tool lifecycle")
    func parsesThreadMessageUsageAndToolLifecycle() {
        // Given
        let raw = #"""
        {"type":"thread.started","thread_id":"thread-1"}
        {"type":"item.started","item":{"id":"item-1","type":"command_execution","command":"echo hi","status":"in_progress"}}
        {"type":"item.completed","item":{"id":"item-1","type":"command_execution","command":"echo hi","aggregated_output":"hi","exit_code":0,"status":"completed"}}
        {"type":"item.completed","item":{"id":"item-2","type":"agent_message","text":"done"}}
        {"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":2,"cache_write_input_tokens":1,"output_tokens":3,"reasoning_output_tokens":4}}
        """#
        let parsed = CodexEventStream.parse(raw)

        // Then
        #expect(parsed.threadIdentifier == "thread-1")
        #expect(parsed.finalText == "done")
        #expect(parsed.usage?["input_tokens"] == 8)
        #expect(parsed.usage?["cache_read_tokens"] == 2)
        #expect(parsed.usage?["cache_write_tokens"] == 1)
        #expect(parsed.usage?["reasoning_output_tokens"] == 4)
        #expect(parsed.toolEvents.count == 1)
        #expect(parsed.toolEvents.first?.name == "Bash")
        #expect(parsed.toolEvents.first?.resultPreview == "hi")
        #expect(parsed.toolEvents.first?.isError == false)
        #expect(parsed.sawThreadStarted)
        #expect(parsed.sawAgentMessage)
        #expect(parsed.sawTurnCompleted)
        #expect(parsed.malformedLineCount == 0)
    }
    
    @Test("a turn that ends on an empty message after a warning item is a successful one")
    func emptyFinalMessageAfterWarningItemIsSuccessful() throws {
        // Given
        let raw = #"""
        {"type":"thread.started","thread_id":"01a20707-d819-75f0-ad2c-3a5ee40d7d1f"}
        {"type":"item.completed","item":{"id":"item_0","type":"error","message":"`[features].multi_agent` is deprecated"}}
        {"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"Running the command once."}}
        {"type":"item.completed","item":{"id":"item_2","type":"command_execution","command":"/bin/zsh -lc date","aggregated_output":"Mon Nov 23 15:13:16 KST 2026\n","exit_code":0,"status":"completed"}}
        {"type":"item.completed","item":{"id":"item_3","type":"agent_message","text":""}}
        {"type":"turn.completed","usage":{"input_tokens":42458,"cached_input_tokens":21120,"cache_write_input_tokens":0,"output_tokens":79,"reasoning_output_tokens":47}}
        """#

        // When
        let sut = CodexEventStream.parse(raw)

        // Then
        try CodexBackend.validateSuccessfulProtocol(sut)
        #expect(sut.finalText == "")
        #expect(sut.failure == nil)
        #expect(sut.toolEvents.count == 1)
    }
    
    @Test("accepts unknown events, counting only broken lines")
    func countsMalformedProtocolLinesWithoutRejectingUnknownEvents() {
        // Given
        let parsed = CodexEventStream.parse(#"""
        not-json
        {"type":"future.event","value":1}
        """#)

        // Then
        #expect(parsed.malformedLineCount == 1)
    }
    
    @Test("parses failure messages")
    func parsesFailureMessage() {
        // Given
        let parsed = CodexEventStream.parse(
        #"{"type":"turn.failed","error":{"message":"model overloaded"}}"#)

        // Then
        #expect(parsed.failure == "model overloaded")
    }
    
    @Test("completed tools are emitted exactly once during a read")
    func emitsEachCompletedToolOnceWhileReading() {
        // Given
        let completed = CompletedCodexTools()
        let reader = CodexEventStream.Reader { sequence, event in
            completed.append(sequence: sequence, event: event)
        }
        
        let now = Date()
        reader.feed(
            line: #"{"type":"item.started","item":{"id":"item-1","type":"command_execution","command":"pwd"}}"#,
            at: now)
        reader.feed(
            line: #"{"type":"item.completed","item":{"id":"item-1","type":"command_execution","command":"pwd","aggregated_output":"/tmp","status":"completed"}}"#,
            at: now)
        reader.feed(
            line: #"{"type":"item.completed","item":{"id":"item-1","type":"command_execution","command":"pwd","aggregated_output":"/tmp","status":"completed"}}"#,
            at: now)

        // Then
        #expect(completed.snapshot.count == 1)
        #expect(completed.snapshot.first?.0 == 0)
        #expect(completed.snapshot.first?.1.resultPreview == "/tmp")
    }
    
    @Test("parses dynamic tool calls of the current codex surface")
    func parsesDynamicToolCallFromCurrentCodexSurface() {
        // Given
        let parsed = CodexEventStream.parse(
        #"{"type":"item.completed","item":{"id":"dynamic-1","type":"dynamic_tool_call","tool":"exec","arguments":{"command":"pwd"},"output":"/tmp","status":"completed"}}"#)

        // Then
        #expect(parsed.toolEvents.count == 1)
        #expect(parsed.toolEvents.first?.name == "exec")
        #expect(parsed.toolEvents.first?.input?.contains("pwd") == true)
        #expect(parsed.toolEvents.first?.resultPreview == "/tmp")
    }
    
    @Test("a broken frame is counted as malformed")
    func invalidUTF8FrameIsMalformed() {
        // Given
        let sut = CodexEventStream.Reader()
        var frame = Data(#"{"type":"result","result":"ok-"#.utf8)
        frame.append(0xFF)
        frame.append(contentsOf: Data(#""}"#.utf8))

        // When
        sut.feed(frame: frame, at: .fixture)

        // Then
        #expect(sut.snapshot().malformedLineCount == 1)
    }
    
    // MARK: - Private
}
