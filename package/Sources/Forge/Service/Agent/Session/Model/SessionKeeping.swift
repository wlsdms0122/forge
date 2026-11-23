//
//  SessionKeeping.swift
//  Forge
//
//  Created by JSilver on 11/22/26.
//

import Foundation

// What the daemon keeps of a session an invoke holds.
enum SessionKeeping: Sendable {
    // The session ends with its invoke.
    case none
    // The session's name and record. `isConfirmed` is whether a turn of this
    // invoke has finished through the record's handle, or the handle is this invoke's own.
    case record(SessionRecord, name: SessionName, isConfirmed: Bool)
}
