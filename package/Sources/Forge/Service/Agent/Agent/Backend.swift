//
//  Backend.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

protocol Backend: Sendable {
    func invoke(_ invocation: AgentInvocation) async throws -> BackendResponse
    func openSession() -> any BackendSession

    // What names the session's conversation to this backend, and the session
    // that value names. A backend that keeps the conversation where a later
    // process can reach it writes both.
    func record(of session: any BackendSession) throws -> JSONValue
    func session(from record: JSONValue) throws -> any BackendSession
}

extension Backend {
    func openSession() -> any BackendSession { NoSession() }

    func record(of session: any BackendSession) throws -> JSONValue {
        throw BackendSessionNotKept("this backend does not keep a session past the invoke that opened it")
    }

    func session(from record: JSONValue) throws -> any BackendSession {
        throw BackendSessionNotKept("this backend does not keep a session past the invoke that opened it")
    }
}
