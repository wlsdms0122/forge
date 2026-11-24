# Workflow Spec

A workflow is a Warp program. It is written in YAML in the notation of the
Warp YAML front end (`warp-frontend-yaml`, its README), which turns it into a
canonical document that the Warp runtime loads, builds and runs. The language
itself, its constructs, types and standard vocabulary, is the Warp
specification's. This page says what Forge adds: how a workflow file is laid
out, and the verbs a workflow writes, which Forge's library declares over the
native procedures the daemon lends a run.

## The file

A workflow is a file written in the YAML notation, and its path is its
identity: `workflow dispatch bot/review.yaml`, a `dispatch` verb, a schedule
and a policy entry all name it so. An absolute path names its file as
written; a relative one names the file under the working directory
(`[directory] working`). The files a workflow reads, prompts and scripts,
are named the same way. A policy matches the path as written, so a path
with an empty, `.` or `..` part is refused. The daemon keeps no list of
workflows: a file is read when something names its path, and it is a
workflow when it builds.

A workflow file is a program of its own. It declares the procedure `main`,
`access: public`, which a run starts from, and may declare other procedures
beside it, which `main` calls by name. The file is read using the library
alone and built against the library, the natives under it and the
standard vocabulary; a file that does not load, has no public `main` or does
not build is refused to whoever names it, with `WorkflowValidationError` and
the reason, and runs nothing. A file is read again
when it changes. A workflow starts another workflow with `dispatch`, as a
run of its own.

An inline spec, handed to `workflow.dispatch` or `schedule.create` in place
of a path, is one procedure written as an object in the same notation, with
no name. It is read the way a file is, as that file's `main`, and runs under
the name `<inline>`. No file is read under that spelling, so a policy entry
for `<inline>` grants inline specs only.

- **Inputs** are the procedure's parameters. A caller hands them by name. An
  input of an optional type (`String?`) may be left out, and the daemon hands
  it null; any other input must be handed.
- **The result** is what the procedure returns, and the run answers that value
  as it is. A workflow that answers with named parts returns a struct or a
  dictionary. A run that fails returns nothing and answers its failure. The
  value leaves the daemon as JSON, so a value JSON cannot hold, a procedure
  or a dictionary two of whose keys are spelled as one text, fails the run
  with `UnwritableValue`.
- **Failures** the body lets out are declared under `failing`, as the language
  asks of any procedure.

An input with a value it takes when left out writes it under `default:`, as
the front end reads it: the input reads `String?` to a caller, so the daemon
hands it null when left out, and the body starts by settling the default.

```yaml
parameters: [ who: { type: String, default: world } ]
```

A workflow's `description:` and each input's `hint:` are prose the front end
hands back beside the document: `workflow describe` prints the description
and each input's hint.

```yaml
procedures:
  main:
    description: Says hello.
    access: public
    parameters: [ who: { type: String, hint: whom to greet } ]
    returns: String
    result: { format: "hello, ${who}", with: { who: { ref: who } } }
```

## The `Forge` library

The verbs are the procedures of Forge's library, a document in the front
end's notation (`lib/Forge.yaml`) that the binary carries, the module
`Forge`. A workflow that writes a verb writes `uses: [Forge]`. A verb is
written by its short name, and its arguments by name, in any order; an
optional one left out is null, and one with a default takes it:

```yaml
- let: listed
  value: { call: { procedure: shell, arguments: { command: [ls, -la], timeout: 30 } } }
- let: reply
  value: { agent: hello }
```

A verb with one argument may be written as a mapping of its name to the
argument, as `agent` is above. A closure handed to a verb takes from the verb
what its signature leaves out, so `invoke`'s body writes only what it returns
and its statements. Every verb may run beside another in a fan-out.

Under each verb is the native procedure the daemon implements,
`Forge.Native.<verb>`, which takes every argument by position, defaults
settled. The natives and the structs they return, `Forge.Run` and
`Forge.Origin`, are the module `Native`, declared in
`lib/Native.interface.warpt`. A workflow writes the library's verbs. One
that names a native or one of those structs writes `uses: [Forge, Native]`,
and a verb's short name then names two procedures, so the verb is written in
full, `Forge.shell`.

A step is a call of a verb that reaches outside the program, from its native's start to its return or throw.

### `Forge.shell`

`shell(command: Array<String>, cwd: String?, env: Dictionary<String, String>, stdin: String?, timeout: Double?) -> String`,
failing `nonzero_exit`, `timeout`. `env` defaults to an empty dictionary.

Runs `command[0]` with the rest as its arguments, holding one of the daemon's
step slots for the whole run, and returns its standard output. `cwd` left out
is the daemon's own, and `env` is set over the daemon's environment. A nonzero
exit fails with `nonzero_exit`, whose details are `exit_code`, `stderr` and
`stdout`. A command still running after `timeout` seconds fails with
`timeout`, whose details are `seconds`.

### `Forge.extract`

`extract(text: String, outputs: Dictionary<String, Any>) -> Dictionary<String, Any>`, const,
failing `extract_refused`.

Reads the values `outputs` names out of `text` (see *Output extractors*) and
returns them by name, with the whole text under `_raw`. It reaches nothing
outside the run. A text that does not hold what `outputs` asks (a path that
is not there and has no `default`, a regex that does not match, a value that
does not coerce to its type) fails with `extract_refused`, which a catch may
take. What `outputs` itself gets wrong (a dictionary that is no extractor, the key
`_raw`, a path or a regex that does not parse) is the workflow's defect: it
is refused before the text is read, and no catch takes it.

### `Forge.invoke`

`invoke(model: String?, allowed: Array<Any>?, env_extra: Dictionary<String, String>, cwd: String?, permission_mode: String?, share_session: Bool, session: String?, on_session_start: (() throws -> Null)?, on_context_start: (() throws -> Null)?, compact: Forge.Compaction, compact_mode: Forge.CompactionMode, timeout: Double?, body: () throws -> some Result) -> some Result`,
failing anything. `env_extra` defaults to an empty dictionary, `share_session` to
`false`, and `compact` and `compact_mode` to their `auto`.

Opens an agent session with these settings and calls `body` inside it; what
the body returns is what `invoke` returns, so the body writes its `returns`.
`model` is `<provider>[:<model>]`; left out, the one registered backend runs
with its own model, and with more than one `invoke` fails with
`BackendNotRegistered`. `allowed` is the list of tools to expose,
each a name or a dictionary of one key to a pattern; left out, the backend's own
setting stands, and `[]` exposes none. A name is `files.read`, `files.write`,
`web`, `delegate` or `schedule`. A dictionary is `{ command: <pattern> }` or
`{ mcp: <pattern> }`, where an mcp pattern is `*`, `<server>.*` or
`<server>.<tool>`. Any other tool fails with `AgentValidationError`.
`permission_mode` is `bypass`, `safe` or `restrict`, and any other value fails
with `AgentValidationError`. `cwd` and `permission_mode` left out are
unset; an empty string is refused. `share_session: true` reuses the session of
an enclosing `invoke` where there is one. An `invoke` still running after
`timeout` seconds fails with `timeout`.

`session` names a session kept past the `invoke`. Left out, the session ends
with the `invoke` that opened it. A name is path components of
`[A-Za-z0-9._-]`, none starting with a dot or ending in `.json`, joined by `/`
(`slack/C123/1700000000.000100`), and whoever knows a name may use it.

- Where no session of that name is kept, the `invoke` makes one from its own
  settings. Where one is, the `invoke` continues its conversation, in this
  run or another, before or after a daemon restart, and the workflow does not
  tell the two apart.
- `model`, `allowed`, `permission_mode`, `compact` and `compact_mode` are the session's: a kept session
  runs with the ones it was made with, and a later `invoke`'s are not read,
  as with `share_session`. `cwd` and `env_extra` are each `invoke`'s own.
- One `invoke` holds a session at a time, for its whole body. Another that
  names it waits in the order it came, holding no step slot, and its
  `timeout` counts the wait. An `invoke` inside a body that already holds the
  name joins it, and none of its settings are read, as with `share_session`.
  A piece of a fan-out inherits no session, so pieces that name one session
  take it in turn. A piece that names a session an `invoke` around the
  fan-out holds is refused: that `invoke` waits for the piece.
- Spellings that differ only in case are one name, kept in lowercase.
- The conversation is the backend's. Where the backend no longer has it when
  an `invoke` takes the session up, the name starts a new conversation with
  the settings it was made with, and the daemon logs `session.lost`. A
  conversation lost after a turn of the `invoke` fails the turn.
- A backend that does not keep a session past its `invoke` fails a named one
  with `BackendSessionNotKept`. The `claude` and `codex` backends keep them
  by the conversation's id, and an OpenAI-compatible one keeps the whole
  conversation in the session's record.
- `session` with `share_session: true` is refused.

A session's life has two events the body of an `invoke` cannot see, and an
`invoke` may bring a closure, a hook, for each. The daemon calls a hook
inside the session, before a turn, once its event has happened and no hook
has run for it since.

- `on_session_start`: the backend opened the session. The session is new,
  with a name or without, or the conversation a kept one named was gone and
  it started over.
- `on_context_start`: the conversation holds none of the context the hook
  builds, what the agent must have read or done before the turns of a body
  mean anything to it. The session started, or the conversation was
  compacted, by the daemon or by a turn.

Where both are due `on_session_start` runs first. A kept session whose hooks
ran does not run them again on the next `invoke`, so a workflow writes them
once and does not ask whether the session is new. The hooks are the
`invoke`'s, not the session's. An `invoke` without one for an event sends its
turns as they are and leaves the event due, and the next `invoke` that
brings one runs it. An `invoke` that joins a session an `invoke` around it
holds uses that one's hooks where it brings none of its own. A hook that
fails fails the turn it ran before, and its event stays due. The turns a
hook sends call for no hook.

A conversation grows with every turn, and each turn reads all of it. As an
`invoke` takes up a kept session, before its first turn, the daemon compacts
the conversation (a summary takes its place) in two cases: its
size is past `[session] context_limit`, or it is past
`[session] cold_compact_floor` and the backend's cache of it has expired, so
the turn would read all of it at full price. The size is what the last
turn's final request carried in; a backend that reports none is not
compacted. The turns of one `invoke` stand on one another, so the daemon
leaves the conversation whole between them: a session without a name, which
ends with its `invoke`, is never compacted by the daemon, and a body that
grows a conversation calls the `compact` step where it can lose the turns
before. `compact` says when the daemon compacts the session, a case of the enum
`Forge.Compaction`: `{ case: auto }` (the default) at the daemon's sizes,
`{ case: none }` never, or `{ case: { limit: { tokens: 300000 } } }` past a
size of its own in place of `context_limit`. Like `model` it is the
session's: a kept session keeps the one it was made with. A turn can compact the conversation too: the backend
on reaching its own limit, or the prompt the turn carried (`/compact` to
`claude`), and such a turn may end with no text. The daemon logs `session.compacted` with the
reason: `limit`, `cold`, `turn` for one a turn did, or `requested` for one a
`compact` step asked for.

Two compactions shrink a conversation. A backend may have one of its own:
`claude` does (`/compact`), and `codex` and an OpenAI-compatible backend have
none. Forge's works on any backend: a turn asks the conversation for a
summary of itself (with the prompt the binary ships, or the one
`[session] compaction_prompt` names), the session opens a new conversation on its backend, and
the first turn that goes into it opens with the summary. The session, its
name and its record stay as they were; `on_session_start` is not due again.
`compact_mode` says whose compaction the session takes, a case of the enum
`Forge.CompactionMode`: `{ case: auto }` (the default) the backend's own
where it has one and Forge's where it has none, `{ case: provider }` the
backend's own, which an `invoke` on a backend without one refuses, or
`{ case: builtin }` Forge's. It covers the compactions the daemon and the
`compact` step start; one a backend does during a turn is the backend's.
`session.compacted` says which in `by`: `provider` or `builtin`.

The `claude` backend's cache stands for an hour. An OpenAI-compatible backend reports a size where its
endpoint counts the request. The `codex` backend reads the size from the
rollout file codex keeps for the thread under `CODEX_HOME` (`~/.codex` where
unset), and reports none where it finds no such file.

A session no `invoke` has used for `[session] retention_days` is dropped, and
its name then starts a new conversation. A session an `invoke` holds or waits
for is not dropped.

`forge session list`, `show` and `delete` read and drop what the daemon keeps.

```yaml
- let: answer
  value:
    call:
      procedure: invoke
      arguments:
        model: claude
        body: { closure: { returns: String, result: { agent: hello } } }
```

### `Forge.agent`

`agent(prompt: String) -> String`, failing `nonzero_exit`.

One prompt turn in the session the enclosing `invoke` opened, holding a step
slot. Outside a session it is refused. A piece of a fan-out speaks to no
session it did not open. A turn its backend refuses (a nonzero exit of the
agent's CLI, an HTTP error below 500) fails with `nonzero_exit`, whose details
are `exit_code`, `stderr` and `stdout`.

### `Forge.compact`

`compact() -> Bool`, failing `nonzero_exit`.

Compacts the conversation of the session the enclosing `invoke` opened,
holding a step slot, whatever the session's `compact` says: it is how a
workflow compacts a session it made with `compact: { case: none }`, or between the
turns of one `invoke`. `true` once the
conversation was compacted, and `false` where there was none to compact: no
turn has gone into the session yet. Outside a session it is refused. The
compaction is logged as `session.compacted` with the reason `requested`, and
`on_context_start` is due after it as after any compaction.

### `Forge.dispatch`

`dispatch(path: String, inputs: Dictionary<String, Any>, timeout: Double?) -> Any`,
failing `child_run_failed`, `timeout`. `inputs` defaults to an empty dictionary.

Runs the workflow at `path` as a run of its own, with its own policy
check, slot and ledger, and returns the value the child returns, as it is.
The child is checked against the policy as `cli:<this workflow's path>`, and
shares this run's root and `parameters`.
The value reads as `Any`, so a parent reads a part of it through a cast. A child that fails at its work fails with `child_run_failed`, which a
catch may take. A child the policy refuses, or one that faults or is
cancelled, fails the parent past any catch.

### `Forge.resource`

`resource(content: String, inputs: Dictionary<String, Any>) -> String`.
`inputs` defaults to an empty dictionary.

Reads the file at the path `content` and
renders it as a template over `inputs`: `${name}` stands for the input of that
name and `$${` writes `${`. A null input is written `null`, as the language's
`format` writes it, and a name the inputs do not hold is refused. An input
that must not be null is declared without `?`.

### `Forge.locate`

`locate(path: String) -> String`.

The absolute path of the file at `path`, which is not read. A path with no
file behind it fails the run with `ResourceError`.

### `Forge.run`

`run() -> Forge.Run`, where `Forge.Run` is `{ run_id: String, root_id: String }`.

This run's id, and the id of the run that started the chain.

### `Forge.origin`

`origin() -> Forge.Origin`, where `Forge.Origin` is `{ kind: String, id: String? }`.

What started this run, and the id of the schedule or caller where there is one.
`kind` is `rpc` for a `workflow.dispatch` call, or the `origin` the caller
hands; `schedule`, with the schedule id, for a schedule fire; `workflow`, with
the parent run id, for a dispatch sent from a run's subprocess; and `manual`,
with no id, for a run a `dispatch` step started.

## Concurrency

Pieces of work run at once through `Standard.Concurrent.allKeyed` (or `all`),
each piece an isolated closure. The front end completes a piece from its slot
and the piece writes what it returns:

```yaml
- let: both
  value:
    call:
      procedure: Standard.Concurrent.allKeyed
      arguments:
        - dictionary:
            left: { closure: { returns: Int, result: 1 } }
            right: { closure: { returns: Int, result: 2 } }
```

## Output extractors

`extract` reads a text, usually what `shell` returned; every other
verb speaks structured values already. The `outputs` argument is a dictionary from a
name to an extractor. Shorthand (bare JSONPath):

```yaml
name: $.user.name
```

Full form:

```yaml
count:
  path: $.total
  type: int
  default: 0
```

Exactly one extractor:

| Field | Notes |
|-------|-------|
| `path` | JSONPath subset (`$`, `$.field`, `$.a.b`, `$.arr[0]`, `$.arr[-1]`, `$.arr[*]`, `$.obj.*`) |
| `regex` | the first capture group, or the whole match when the pattern has none; multi-line OK |
| `line` | 0-indexed (negative counts from end) |

Modifiers:

| Field | Notes |
|-------|-------|
| `type` | `string` (default) / `int` / `float` / `bool` / `json`, coerced to it |
| `default` | fallback value when missing. A declared `default` (even `null`) means a missing path does not fail the call; leaving `default` out makes the path mandatory, and a missing one fails the call with `extract_refused` |

## A complete workflow

A tour of the language a workflow is written in, with no verb that reaches
outside the run.

```yaml runnable
procedures:
  main:
    access: public
    parameters: [ who: { type: String, default: world } ]
    returns: "Dictionary<String, Any>"
    failing: [aborted, concurrent_failed]
    body:
      - let: greeting
        value: { format: "hello, ${who}", with: { who: { ref: who } } }
      - var: branch
        type: String
        value: ""
      - value:
          cases:
            - when: { of: { ref: who }, is: world }
              then: [ { set: branch, value: took-a } ]
            - else: [ { set: branch, value: took-b } ]
      - var: rounds
        type: Int
        value: 0
      - value:
          loop:
            while: { of: { ref: rounds }, is_not: 2 }
            body:
              - set: rounds
                value: { of: { ref: rounds }, plus: 1 }
      - var: walk
        type: "Array<String>"
        value: []
      - let: walked
        value:
          each:
            of: [ one, two ]
            as: item
            index: at
            body:
              - set: walk
                value: { of: { ref: walk }, appending: { format: "${at}:${item}", with: { at: { ref: at }, item: { ref: item } } } }
      - let: parallel
        value:
          call:
            procedure: Standard.Concurrent.allKeyed
            arguments:
              - dictionary:
                  - [left, { closure: { returns: Int, result: 1 } }]
                  - [right, { closure: { returns: Int, result: 2 } }]
      - var: rescued
        type: String
        value: ""
      - let: caught
        value:
          try:
            body:
              - value: { abort: bail out }
            catch:
              - set: rescued
                value: { format: "rescued: ${message}", with: { message: { ref: caught.message } } }
    result:
      dictionary:
        - [greeting, { ref: greeting }]
        - [branch, { ref: branch }]
        - [loop, { ref: rounds }]
        - [walk, { ref: walk }]
        - [parallel, { ref: parallel }]
        - [rescued, { ref: rescued }]
```
