//
//  AgentService+Testing.swift
//  ForgeTests
//
//  Created by JSilver on 11/22/26.
//

import Foundation
@testable import Forge

extension AgentService {
    // A live agent over a session directory of its own, for tests that keep no session.
    init(executor: AgentExecutor) {
        self.init(
            executor: executor,
            sessions: SessionStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("forge-sessions-\(UUID().uuidString)", isDirectory: true)
            )
        )
    }
}
