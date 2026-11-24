//
//  ClaudeBackend.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct ClaudeBackend: CompactingBackend {
    // MARK: - Property
    // What claude writes to stderr when `--resume` names a conversation it does not have.
    private static let missingConversation = "No conversation found with session ID"
    
    let executable: String
    let translator: ClaudeTranslator
    // The one-hour prompt cache claude code writes its conversations to.
    let cacheLifetime: Duration? = .seconds(3600)
    
    // MARK: - Initializer
    init(executable: String = "claude", translator: ClaudeTranslator = ClaudeTranslator()) {
        self.executable = executable
        self.translator = translator
    }
    
    // MARK: - Public
    static func validateSuccessfulProtocol(_ parsed: StreamParseResult, turn: Int? = nil) throws {
        let location = turn.map { turn in " (turn \(turn))" } ?? ""
        
        guard parsed.malformedLineCount == 0 else {
            throw BackendProtocolViolation(
                "claude emitted \(parsed.malformedLineCount) malformed stream"
                    + " frame(s)\(location)"
            )
        }
        
        guard parsed.sawTerminalResult else {
            throw BackendProtocolViolation(
                "claude successful turn omitted its terminal result envelope\(location)"
            )
        }
    }
    
    static func failureDetail(stderr: String, stdout: String) -> String {
        let error = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !error.isEmpty { return String(error.prefix(300)) }
        
        let detail = ResponseExtract.text(Diagnostics.lastLine(stdout))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return String(detail.prefix(300))
    }
    
    static func buildArgs(
        configuration: ClaudeAgentConfiguration,
        user: String,
        outputFormat: String,
        session: [String] = [],
        extra: [String]
    ) -> [String] {
        var arguments: [String] = ["--print", "-p", user]
        
        if let model = configuration.model { arguments += ["--model", model] }
        
        arguments += session
        
        if let mode = configuration.permissionMode {
            arguments += ["--permission-mode", mode]
        }
        
        arguments += ["--output-format", outputFormat]
        
        if let tools = configuration.availableTools {
            arguments += ["--tools", tools.joined(separator: ",")]
        }
        
        if let allowed = configuration.allowedTools {
            arguments += ["--allowedTools", allowed.joined(separator: " ")]
        }
        
        arguments += extra
        
        return arguments
    }
    
    func invoke(_ invocation: AgentInvocation) async throws -> BackendResponse {
        let translated = try translator.translate(invocation.agent)
        let native = translated.value
        
        await AgentEventLog.translation(
            invocationID: invocation.id,
            backend: "claude",
            diagnostics: translated.diagnostics
        )
        
        let claudeSession = invocation.session as? ClaudeSession
        let index = claudeSession?.turnIndex ?? 0
        let started = ContinuousClock.now
        
        try Task.checkCancellation()
        
        let output = try await run(invocation.prompt, in: claudeSession, configuration: native)
        let parsed = output.parsed
        let toolEvents = parsed.toolEvents
        
        for (sequence, event) in toolEvents.enumerated() {
            await AgentEventLog.tool(
                invocationID: invocation.id,
                model: invocation.agent.model?.displayName,
                turn: index,
                sequence: sequence,
                name: event.name,
                input: event.input,
                resultPreview: event.resultPreview,
                isError: event.isError,
                durationMilliseconds: event.durationMs,
                startedAt: event.startedAt,
                completedAt: event.completedAt
            )
        }
        
        try Self.validateSuccessfulProtocol(parsed, turn: index)
        
        let text = parsed.finalText
        let usage = parsed.usage?.agentUsage
        claudeSession?.turnIndex = index + 1
        
        let durationMs = (ContinuousClock.now - started).milliseconds
        
        return BackendResponse(
            text: text,
            usage: (usage?.isEmpty ?? true) ? nil : usage,
            toolEvents: toolEvents,
            stdoutLength: output.stdoutLength,
            durationMs: durationMs,
            contextTokens: parsed.contextTokens,
            isCompacted: parsed.sawCompaction
        )
    }
    
    func openSession() -> any BackendSession {
        ClaudeSession(sessionID: UUID().uuidString)
    }
    
    func record(of session: any BackendSession) throws -> JSONValue {
        guard let session = session as? ClaudeSession else {
            throw BackendSessionNotKept("the session is not one claude opened")
        }
        
        return [
            "session_id": .string(session.sessionID),
            "turn_index": .int(session.turnIndex),
            "established": .bool(session.established)
        ]
    }
    
    func session(from record: JSONValue) throws -> any BackendSession {
        guard
            let sessionID = record["session_id"]?.stringValue,
            let turnIndex = record["turn_index"]?.intValue
        else {
            throw BackendSessionNotKept("the record does not name a claude session")
        }
        
        // A record that does not say is of a conversation claude has.
        return ClaudeSession(
            sessionID: sessionID,
            turnIndex: turnIndex,
            established: record["established"]?.boolValue ?? true
        )
    }
    
    func compact(
        _ session: any BackendSession,
        turn: @Sendable (String) async throws -> BackendResponse
    ) async throws -> BackendResponse {
        try await turn("/compact")
    }
    
    // MARK: - Private
    // One claude process over the session's conversation, and what it wrote.
    // A turn outside a session runs in a conversation of its own.
    private func run(
        _ prompt: String,
        in session: ClaudeSession?,
        configuration: ClaudeAgentConfiguration
    ) async throws -> (parsed: StreamParseResult, stdoutLength: Int) {
        let sessionID = session?.sessionID ?? UUID().uuidString
        let index = session?.turnIndex ?? 0
        let established = session?.established ?? false
        let arguments = Self.buildArgs(
            configuration: configuration,
            user: prompt,
            outputFormat: "stream-json",
            session: established ? ["--resume", sessionID] : ["--session-id", sessionID],
            extra: ["--verbose"]
        )
        let reader = StreamJSON.Reader()
        let lineHandler: Subprocess.StdoutLineHandler = { (frame: Data, at: Date) in
            reader.feed(frame: frame, at: at)
        }
        let result = try await Subprocess.run(
            executable: executable,
            args: arguments,
            cwd: configuration.workingDirectory,
            envExtra: configuration.environment,
            stdin: "",
            onStdoutLine: lineHandler
        )
        
        session?.established = true
        
        try Task.checkCancellation()
        
        guard result.exitCode == 0 else {
            let exit = BackendNonzeroExit(
                "claude exit \(result.exitCode) (turn \(index)):"
                    + " \(Self.failureDetail(stderr: result.stderr, stdout: result.stdout))",
                exitCode: result.exitCode,
                stderr: result.stderr,
                stdout: result.stdout
            )
            
            if established, result.stderr.contains(Self.missingConversation) {
                throw BackendSessionLost(
                    "claude has no conversation for session \(sessionID) (turn \(index))",
                    exit: exit
                )
            }
            
            throw exit
        }
        
        return (reader.snapshot(), result.stdout.count)
    }
}
