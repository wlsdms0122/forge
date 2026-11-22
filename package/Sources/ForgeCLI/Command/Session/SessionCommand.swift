//
//  SessionCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 11/22/26.
//

import ArgumentParser
import Foundation

struct SessionCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "List, show and delete the agent sessions kept by name.",
        discussion: """
            An `invoke` that names a `session` speaks through a conversation that
            outlives it: the next `invoke` with the same name continues where the
            last one stopped, in this run or another, before or after a daemon
            restart. The daemon keeps the name, the order and the settings the
            session was made with; the conversation itself stays with the backend.
            
            One `invoke` holds a session at a time. Others that name it wait in
            the order they came, and `list` shows who is held and how many wait.
            
            `delete` drops the daemon's record, so the name starts a new
            conversation the next time it is used. It leaves the backend's own
            copy of the conversation alone.
            """,
        subcommands: [
            SessionListCommand.self,
            SessionShowCommand.self,
            SessionDeleteCommand.self,
        ]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
