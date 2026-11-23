//
//  SessionStoreTests.swift
//  ForgeTests
//
//  Created by JSilver on 11/22/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("SessionStore Tests")
struct SessionStoreTests {
    // MARK: - Property
    private let temporary = TemporaryDirectory("sessionstore")
    
    // MARK: - Initializer
    // MARK: - Test
    @Test("a record written under a path name reads back under that name")
    func recordReadsBackUnderItsName() async throws {
        // Given
        let sut = SessionStore(directory: try temporary.make("roundtrip"))
        let record = Self.record(turns: 3)
        
        // When
        try await sut.write(record, for: try SessionName("slack/c123/1700000000.000100"))
        
        // Then
        #expect(try await sut.record(try SessionName("slack/c123/1700000000.000100")) == record)
        #expect(try await sut.record(try SessionName("slack/c123")) == nil)
        #expect(await sut.all().map(\.name.rawValue) == ["slack/c123/1700000000.000100"])
    }
    
    @Test("a record outlives the store that wrote it")
    func recordOutlivesTheStore() async throws {
        // Given
        let directory = try temporary.make("restart")
        let record = Self.record(turns: 1)
        
        try await SessionStore(directory: directory).write(record, for: try SessionName("review/survey"))
        
        // When
        let sut = SessionStore(directory: directory)
        
        // Then
        #expect(try await sut.record(try SessionName("review/survey")) == record)
    }
    
    @Test("a directory reached through a link lists its sessions by the same names")
    func linkedDirectoryListsTheSameNames() async throws {
        // Given
        let directory = try temporary.make("target")
        let link = temporary.url.appendingPathComponent("link-\(UUID().uuidString)")
        
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        
        let sut = SessionStore(directory: link)
        
        // When
        try await sut.write(Self.record(turns: 1), for: try SessionName("slack/c1/t1"))
        
        // Then
        #expect(await sut.all().map(\.name.rawValue) == ["slack/c1/t1"])
    }
    
    @Test(
        "a name that is not path components of safe characters is refused",
        arguments: ["", "/lead", "trail/", "a//b", "../up", ".hidden", "a/.b", "sp ace", "a\\b", "café", "a.json/b", "a.json", "a.JSON/b"]
    )
    func unsafeNameIsRefused(name: String) {
        // When / Then
        #expect(throws: SessionStoreError.self) {
            _ = try SessionName(name)
        }
    }
    
    @Test("delete removes the record and the directories its name alone used")
    func deleteRemovesRecordAndEmptyDirectories() async throws {
        // Given
        let directory = try temporary.make("delete")
        let sut = SessionStore(directory: directory)
        
        try await sut.write(Self.record(turns: 1), for: try SessionName("slack/c1/t1"))
        try await sut.write(Self.record(turns: 1), for: try SessionName("slack/c2/t2"))
        
        // When
        try await sut.delete(try SessionName("slack/c1/t1"))
        
        // Then
        #expect(await sut.all().map(\.name.rawValue) == ["slack/c2/t2"])
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("slack/c1").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("slack/c2").path))
    }
    
    @Test("delete refuses a held session and a name with no record")
    func deleteRefusesHeldAndMissing() async throws {
        // Given
        let sut = SessionStore(directory: try temporary.make("held"))
        
        try await sut.write(Self.record(turns: 1), for: try SessionName("kept"))
        try await sut.acquire(try SessionName("kept"))
        
        // When / Then
        await #expect(throws: SessionStoreError.self) { try await sut.delete(try SessionName("kept")) }
        await #expect(throws: SessionStoreError.self) { try await sut.delete(try SessionName("absent")) }
        
        await sut.release(try SessionName("kept"))
        try await sut.delete(try SessionName("kept"))
        
        #expect(try await sut.record(try SessionName("kept")) == nil)
    }
    
    @Test("spellings that differ only in case are one name")
    func spellingsDifferingInCaseAreOneName() throws {
        #expect(try SessionName("Slack/C1") == SessionName("slack/c1"))
        #expect(try SessionName("Slack/C1").rawValue == "slack/c1")
    }
    
    @Test("those who wait for a held name take it in the order they came")
    func waitersEnterInOrder() async throws {
        // Given
        let sut = SessionStore(directory: try temporary.make("line"))
        let order = OrderedCollector<Int>()
        
        try await sut.write(Self.record(turns: 1), for: try SessionName("line"))
        try await sut.acquire(try SessionName("line"))
        
        // When
        var waiters: [Task<Void, Error>] = []
        
        for index in 1...3 {
            waiters.append(
                Task {
                    try await sut.acquire(try SessionName("line"))
                    order.append(index)
                    await sut.release(try SessionName("line"))
                }
            )
            
            // Each waiter is in the line before the next one comes.
            while try await sut.entry(try SessionName("line")).waiting < index { await Task.yield() }
        }
        
        await sut.release(try SessionName("line"))
        
        for waiter in waiters { try await waiter.value }
        
        // Then
        #expect(order.elements == [1, 2, 3])
        #expect(try await sut.entry(try SessionName("line")).isHeld == false)
    }
    
    @Test("a waiter that is cancelled leaves the line, and the name still passes on")
    func cancelledWaiterLeavesTheLine() async throws {
        // Given
        let sut = SessionStore(directory: try temporary.make("cancel"))
        
        try await sut.write(Self.record(turns: 1), for: try SessionName("line"))
        try await sut.acquire(try SessionName("line"))
        
        let abandoned = Task { try await sut.acquire(try SessionName("line")) }
        
        while try await sut.entry(try SessionName("line")).waiting < 1 { await Task.yield() }
        
        // When
        abandoned.cancel()
        
        // Then
        await #expect(throws: CancellationError.self) { try await abandoned.value }
        #expect(try await sut.entry(try SessionName("line")).waiting == 0)
        
        await sut.release(try SessionName("line"))
        try await sut.acquire(try SessionName("line"))
        await sut.release(try SessionName("line"))
    }
    
    @Test("expiry drops the sessions last used before the moment, and no session an invoke holds")
    func expiryDropsSessionsLastUsedBeforeTheMoment() async throws {
        // Given
        let sut = SessionStore(directory: try temporary.make("expire"))
        let old = try SessionName("old/one")
        let held = try SessionName("held")
        let recent = try SessionName("recent")
        
        try await sut.write(Self.record(turns: 1, usedAt: "2026-11-01T09:00:00Z"), for: old)
        try await sut.write(Self.record(turns: 1, usedAt: "2026-11-01T09:00:00Z"), for: held)
        try await sut.write(Self.record(turns: 1, usedAt: "2026-11-20T09:00:00Z"), for: recent)
        try await sut.acquire(held)
        
        // When
        let expired = await sut.expire(before: try #require(ISO8601.parse("2026-11-15T00:00:00Z")))
        
        // Then
        #expect(expired == [old])
        #expect(await sut.all().map(\.name) == [held, recent])
        
        await sut.release(held)
    }
    
    // MARK: - Private
    private static func record(turns: Int, usedAt: String = "2026-11-22T09:05:00Z") -> SessionRecord {
        SessionRecord(
            provider: "claude",
            handle: ["session_id": "S-1", "turn_index": .int(turns)],
            model: "claude:haiku",
            allowed: ["files.read", ["command": "git *"]],
            permissionMode: "safe",
            createdAt: "2026-11-22T09:00:00Z",
            usedAt: usedAt,
            turns: turns,
            compact: .automatic
        )
    }
}
