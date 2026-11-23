//
//  SessionSweeper.swift
//  Forge
//
//  Created by JSilver on 11/22/26.
//

import Foundation

// Drops the sessions no invoke has used for the retention, once as it starts
// and then every interval.
actor SessionSweeper {
    // MARK: - Property
    private let store: SessionStore
    private let retention: Duration
    private let interval: Duration
    
    private var task: Task<Void, Never>?
    
    // MARK: - Initializer
    init(store: SessionStore, retention: Duration, interval: Duration = .seconds(3600)) {
        self.store = store
        self.retention = retention
        self.interval = interval
    }
    
    // MARK: - Public
    func start() async {
        stop()
        
        await sweep()
        
        let interval = interval
        
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                
                if Task.isCancelled { return }
                
                await self?.sweep()
            }
        }
    }
    
    func stop() {
        task?.cancel()
        task = nil
    }
    
    func sweep() async {
        let moment = Date().addingTimeInterval(-Double(retention.components.seconds))
        
        for name in await store.expire(before: moment) {
            await Log.shared.append(
                "session.expired",
                LogPayload(["session": name.rawValue]),
                category: "session"
            )
        }
    }
    
    // MARK: - Private
}
