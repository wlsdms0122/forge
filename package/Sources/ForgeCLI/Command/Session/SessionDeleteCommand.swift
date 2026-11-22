//
//  SessionDeleteCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 11/22/26.
//

import ArgumentParser
import Foundation
import Forge

struct SessionDeleteCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a kept session, so its name starts a new conversation.",
        discussion: """
            Removes the daemon's record of the session. A session an `invoke`
            holds is refused. The backend's own copy of the conversation is
            left alone.
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Session name.")
    var name: String
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "session delete")
        
        client.call("session.delete", ["name": .string(name)]).printResult(json: json)
    }
    
    // MARK: - Private
}
