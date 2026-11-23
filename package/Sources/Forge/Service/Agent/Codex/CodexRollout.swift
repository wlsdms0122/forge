//
//  CodexRollout.swift
//  Forge
//
//  Created by JSilver on 11/23/26.
//

import Foundation

// The files codex writes a thread's events to, under its home. The frames of
// `codex exec --json` do not carry the size of a conversation; the rollout's
// `token_count` events do, one for each call to the model.
struct CodexRollout {
    // MARK: - Property
    let home: URL
    
    // MARK: - Initializer
    init(home: URL) {
        self.home = home
    }
    
    // The home a codex process started with this environment writes to.
    init(environment: [String: String]) {
        if let home = environment["CODEX_HOME"], !home.isEmpty {
            self.init(home: URL(fileURLWithPath: home))
        } else {
            let user = environment["HOME"].map { path in URL(fileURLWithPath: path) }
                ?? FileManager.default.homeDirectoryForCurrentUser
            
            self.init(home: user.appendingPathComponent(".codex"))
        }
    }
    
    // MARK: - Public
    // Codex starts a file each time a thread's history is rewound, named after
    // the moment it starts, and writes on in the newest.
    func file(of threadIdentifier: String) -> URL? {
        let sessions = home.appendingPathComponent("sessions")
        
        guard
            let files = FileManager.default.enumerator(
                at: sessions,
                includingPropertiesForKeys: nil
            )
        else {
            return nil
        }
        
        return files
            .compactMap { file in file as? URL }
            .filter { file in
                let name = file.lastPathComponent
                
                return name.hasPrefix("rollout-")
                    && (name.hasSuffix("-\(threadIdentifier).jsonl")
                        || name.contains("-\(threadIdentifier)_") && name.hasSuffix(".jsonl"))
            }
            .max { left, right in left.lastPathComponent < right.lastPathComponent }
    }
    
    // What the last call to the model the file tells of held and answered,
    // which is the conversation as its last turn ended.
    func contextTokens(in file: URL) -> Int? {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return nil }
        
        var end = data.endIndex
        
        while end > data.startIndex {
            let start = data[data.startIndex..<end].lastIndex(of: UInt8(ascii: "\n"))
                .map { newline in data.index(after: newline) } ?? data.startIndex
            
            if let size = contextTokens(inEvent: data[start..<end]) { return size }
            
            end = start > data.startIndex ? data.index(before: start) : data.startIndex
        }
        
        return nil
    }
    
    // MARK: - Private
    private func contextTokens(inEvent line: Data) -> Int? {
        guard
            line.range(of: Data("\"token_count\"".utf8)) != nil,
            let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let payload = event["payload"] as? [String: Any],
            payload["type"] as? String == "token_count",
            let info = payload["info"] as? [String: Any],
            let usage = info["last_token_usage"] as? [String: Any],
            let inputTokens = usage["input_tokens"] as? Int
        else {
            return nil
        }
        
        return inputTokens + (usage["output_tokens"] as? Int ?? 0)
    }
}
