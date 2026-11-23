//
//  FakeCodex.swift
//  ForgeTests
//
//  Created by JSilver on 11/23/26.
//

import Foundation

// A codex executable that answers every turn and keeps what each was called
// with. A turn that resumes no thread starts `thread-<n>`, and the usage it
// reports grows by ten input tokens a call, as a thread's total does. A resume
// of a thread it lost fails the way codex does, with nothing on stdout. Where
// `CODEX_HOME` is set, the thread's rollout there takes a `token_count` a call
// whose last call held a hundred input tokens a call.
struct FakeCodex {
    struct Call: Equatable {
        // MARK: - Property
        let arguments: [String]
        let prompt: String

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let directory: URL

    var executable: URL { directory.appendingPathComponent("fakecodex") }

    // MARK: - Initializer
    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-codex-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let script = #"""
            #!/bin/sh
            home=$(dirname "$0")
            call=$(($(cat "$home/calls" 2>/dev/null || echo 0) + 1))
            echo "$call" > "$home/calls"
            printf '%s\n' "$@" > "$home/arguments.$call"
            cat > "$home/prompt.$call"
            thread=
            for argument in "$@"; do
              case "$argument" in thread-*) thread=$argument ;; esac
            done
            if [ -n "$thread" ] && grep -qx "$thread" "$home/lost" 2>/dev/null; then
              echo "Error: thread/resume: thread/resume failed: no rollout found for thread id $thread (code -32600)" >&2
              exit 1
            fi
            if [ -z "$thread" ]; then
              started=$(($(cat "$home/threads" 2>/dev/null || echo 0) + 1))
              echo "$started" > "$home/threads"
              thread="thread-$started"
            fi
            if [ -n "$CODEX_HOME" ]; then
              mkdir -p "$CODEX_HOME/sessions/2026/11/23"
              echo "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":$((call * 100)),\"output_tokens\":$call}}}}" \
                >> "$CODEX_HOME/sessions/2026/11/23/rollout-2026-11-23T15-11-24-$thread.jsonl"
              echo "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}" \
                >> "$CODEX_HOME/sessions/2026/11/23/rollout-2026-11-23T15-11-24-$thread.jsonl"
            fi
            echo "{\"type\":\"thread.started\",\"thread_id\":\"$thread\"}"
            echo "{\"type\":\"item.completed\",\"item\":{\"id\":\"a\",\"type\":\"agent_message\",\"text\":\"answer $call\"}}"
            echo "{\"type\":\"turn.completed\",\"usage\":{\"input_tokens\":$((call * 10)),\"output_tokens\":$call}}"
            """#

        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    // MARK: - Public
    func calls() throws -> [Call] {
        let count = Int(try read("calls").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        return try (1...max(count, 1)).prefix(count).map { call in
            Call(
                arguments: try read("arguments.\(call)").split(separator: "\n").map(String.init),
                prompt: try read("prompt.\(call)")
            )
        }
    }

    func lose(_ thread: String) throws {
        let lost = (try? read("lost")) ?? ""

        try (lost + thread + "\n").write(
            to: directory.appendingPathComponent("lost"),
            atomically: true,
            encoding: .utf8
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Private
    private func read(_ name: String) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }
}
