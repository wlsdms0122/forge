//
//  SessionStore.swift
//  Forge
//
//  Created by JSilver on 11/22/26.
//

import Foundation

// The named sessions of this daemon: one record file per name under the
// directory, and one line per name so that a single invoke speaks through a
// session at a time. A name is the record's path under the directory.
actor SessionStore {
    private struct Waiter {
        // MARK: - Property
        let id: UInt64
        let continuation: CheckedContinuation<Void, Error>
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    private let directory: URL
    
    // A name is a key while an invoke holds it; the value is who waits behind.
    private var lines: [SessionName: [Waiter]] = [:]
    private var waiterSequence: UInt64 = 0
    
    // MARK: - Initializer
    init(directory: URL) {
        self.directory = directory
    }
    
    // MARK: - Public
    // Returns once the caller holds the name. Callers leave in the order they came.
    func acquire(_ name: SessionName) async throws {
        try Task.checkCancellation()
        
        guard lines[name] != nil else {
            lines[name] = []
            
            return
        }
        
        let id = waiterSequence
        waiterSequence &+= 1
        
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    lines[name, default: []].append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.abandon(name, waiter: id) }
        }
    }
    
    func release(_ name: SessionName) {
        guard var waiters = lines[name] else { return }
        
        guard !waiters.isEmpty else {
            lines[name] = nil
            
            return
        }
        
        let next = waiters.removeFirst()
        lines[name] = waiters
        next.continuation.resume()
    }
    
    func record(_ name: SessionName) throws -> SessionRecord? {
        let file = file(of: name)
        
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        
        do {
            return try JSONDecoder().decode(SessionRecord.self, from: Data(contentsOf: file))
        } catch {
            throw SessionStoreError.unreadable(name.rawValue, reason: "\(error)")
        }
    }
    
    func write(_ record: SessionRecord, for name: SessionName) throws {
        let file = file(of: name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(record).write(to: file, options: .atomic)
    }
    
    func delete(_ name: SessionName) throws {
        let file = file(of: name)
        
        guard lines[name] == nil else { throw SessionStoreError.held(name.rawValue) }
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw SessionStoreError.notFound(name.rawValue)
        }
        
        try FileManager.default.removeItem(at: file)
        removeEmptyDirectories(above: file)
    }
    
    // Drops every session last used before the moment, and returns their
    // names. A session an invoke holds is in use whatever its record says.
    func expire(before moment: Date) -> [SessionName] {
        names().filter { name in
            guard
                lines[name] == nil,
                let record = try? record(name),
                let usedAt = ISO8601.parse(record.usedAt),
                usedAt < moment
            else {
                return false
            }
            
            return (try? delete(name)) != nil
        }
    }
    
    func entry(_ name: SessionName) throws -> SessionEntry {
        guard let record = try record(name) else { throw SessionStoreError.notFound(name.rawValue) }
        
        return entry(name, record)
    }
    
    // Every session whose record reads. A record that does not read is left
    // to `entry`, which says why.
    func all() -> [SessionEntry] {
        names().compactMap { name in
            guard let record = try? record(name) else { return nil }
            
            return entry(name, record)
        }
    }
    
    // MARK: - Private
    private func file(of name: SessionName) -> URL {
        directory.appendingPathComponent("\(name.rawValue).\(SessionName.recordExtension)")
    }
    
    private func entry(_ name: SessionName, _ record: SessionRecord) -> SessionEntry {
        SessionEntry(
            name: name,
            record: record,
            isHeld: lines[name] != nil,
            waiting: lines[name]?.count ?? 0
        )
    }
    
    private func names() -> [SessionName] {
        let suffix = ".\(SessionName.recordExtension)"
        var names: [SessionName] = []
        
        // Paths come back relative to the directory, so a directory reached
        // through a link names its sessions the same.
        let enumerator = FileManager.default.enumerator(atPath: directory.path)
        
        while let path = enumerator?.nextObject() as? String {
            guard
                path.hasSuffix(suffix),
                enumerator?.fileAttributes?[.type] as? FileAttributeType == .typeRegular
            else {
                continue
            }
            
            // A file whose path is no name was not written by this store.
            guard let name = try? SessionName(String(path.dropLast(suffix.count))) else { continue }
            
            names.append(name)
        }
        
        return names.sorted { left, right in left.rawValue < right.rawValue }
    }
    
    private func abandon(_ name: SessionName, waiter id: UInt64) {
        guard
            var waiters = lines[name],
            let index = waiters.firstIndex(where: { waiter in waiter.id == id })
        else {
            return
        }
        
        let waiter = waiters.remove(at: index)
        lines[name] = waiters
        waiter.continuation.resume(throwing: CancellationError())
    }
    
    // A name's directories exist for its record, so they go with the last one in them.
    private func removeEmptyDirectories(above file: URL) {
        let root = directory.standardizedFileURL.path
        var parent = file.deletingLastPathComponent().standardizedFileURL
        
        while parent.path.hasPrefix(root + "/") {
            guard (try? FileManager.default.contentsOfDirectory(atPath: parent.path))?.isEmpty == true else { return }
            
            try? FileManager.default.removeItem(at: parent)
            parent = parent.deletingLastPathComponent().standardizedFileURL
        }
    }
}
