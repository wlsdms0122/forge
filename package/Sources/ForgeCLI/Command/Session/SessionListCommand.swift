//
//  SessionListCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 11/22/26.
//

import ArgumentParser
import Foundation
import Forge

struct SessionListCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List the kept sessions, with who is held and how many wait."
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let client = Client(global, context: "session list")
        let result = client.call("session.list", [:])
        
        if json {
            result.printJSON()
            
            return
        }
        
        let sessions = result["sessions"]?.arrayValue ?? []
        
        if sessions.isEmpty {
            print("(no sessions)")
            
            return
        }
        
        for session in sessions {
            let name = session["name"]?.stringValue ?? "?"
            let provider = session["provider"]?.stringValue ?? "?"
            let turns = session["turns"]?.intValue ?? 0
            let used = session["used_at"]?.stringValue ?? "?"
            let held = (session["held"]?.boolValue ?? false) ? " ●held" : ""
            let waiting = (session["waiting"]?.intValue).flatMap { count in
                count > 0 ? " (\(count) waiting)" : nil
            } ?? ""
            
            let context = (session["context_tokens"]?.intValue).map { tokens in "\tcontext \(tokens)" } ?? ""
            
            print("\(name)\t[\(provider)]\(held)\(waiting)\tturns \(turns)\(context)\tused \(used)")
        }
    }
    
    // MARK: - Private
}
