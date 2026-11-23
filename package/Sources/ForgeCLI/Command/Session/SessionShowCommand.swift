//
//  SessionShowCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 11/22/26.
//

import ArgumentParser
import Foundation
import Forge

struct SessionShowCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show a kept session in full (settings, backend handle, line)."
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Session name.")
    var name: String
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "session show")
        
        client.call("session.show", ["name": .string(name)]).printResult(json: json)
    }
    
    // MARK: - Private
}
