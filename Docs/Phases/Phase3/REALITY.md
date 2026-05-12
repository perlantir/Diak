# Phase 3 — Chat + Canvas — Reality Investigation

Direct observation captured 2026-05-11/12 against the live Hermes
Agent v0.13.0 stack on this Mac. Every protocol-level claim is
backed by a captured SSE byte dump in `Docs/Phases/Phase3/evidence/`,
a source-line reference into `~/.hermes/hermes-agent/`, or a probe
run script in `/tmp/sse_*.sh`. Library-evaluation claims cite
GitHub URLs and commit dates. Speculation is excluded by design.

Out of scope per WU3.1: any production source modification. This
document is investigation only; SCOPE.md gets written after this
doc is ratified.

## Investigation Area 1 — SSE event flow under five scenarios

### Two distinct streaming surfaces

The Hermes API Server exposes two SSE-bearing endpoints with
**different event shapes**:

| Endpoint | Format | Tool events | Reasoning | Terminator |
|---|---|---|---|---|
| `POST /v1/chat/completions` (`stream: true`) | OpenAI-compatible `chat.completion.chunk` | Out-of-band `event: hermes.tool.progress` lines | Not surfaced | `data: [DONE]` |
| `GET /v1/runs/{run_id}/events` | Hermes-native `{"event":"…", …}` | In-band `tool.started` / `tool.completed` | In-band `reasoning.available` | `{"event":"run.completed"}` + `: stream closed` SSE comment |

Both surfaces share the same underlying execution path — they're
two views of the same agent run. The `/v1/runs` shape is **richer
and cleaner** for Diak's purposes (cleaner tool events, native
reasoning event, explicit run.completed terminator, the
`POST /v1/runs/{id}/stop` companion). Capabilities probe:
`evidence/api_server_capabilities.json`.

Key capabilities flag: `"tool_execution": "server"` — the server
executes tools inside its own Hermes AIAgent. Diak does not get a
hook between "model decided to call tool" and "tool executed."
Evidence:
```json
"runtime": {
  "mode": "server_agent",
  "tool_execution": "server",
  "split_runtime": false,
  "description": "The API server creates a server-side Hermes
                  AIAgent; tools execute on the API-server host
                  unless a future explicit split-runtime mode is
                  enabled."
}
```

### Scenario A — Simple text response

Prompt: "Reply with exactly: hello." Evidence:
`evidence/sse_a_simple_text.txt` (3 events, 8 lines).

```
data: {"id":"chatcmpl-…","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}

data: {"id":"chatcmpl-…","choices":[{"index":0,"delta":{"content":"hello"},"finish_reason":null}]}

data: {"id":"chatcmpl-…","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":27020,"completion_tokens":16,"total_tokens":27036}}

data: [DONE]
```

Shape per chunk:
- `id` — chunk id (same id across all chunks of one response)
- `object: "chat.completion.chunk"`
- `created` — Unix timestamp
- `model` — echoes request model name
- `choices: [{index, delta, finish_reason}]`
  - First chunk: `delta: {"role":"assistant"}`
  - Middle chunks: `delta: {"content": "<token>"}`
  - Final chunk: `delta: {}` plus `finish_reason: "stop"` plus
    top-level `usage` object
- Terminator: literal `data: [DONE]` (no JSON wrapping)
- Separator: **blank line** between events (standard SSE
  semantics)

**Note for Phase 3 token-streaming UI.** Short replies may
collapse into a single content-delta chunk; longer replies stream
one token per chunk (next scenario confirms).

### Scenario A2 — Longer text response

Prompt: "Write a single paragraph (3-4 sentences) about the
moon." Evidence: `evidence/sse_a2_longer_text.txt` (160 lines,
73 events).

Output: 112 completion tokens delivered as **roughly one token per
chunk**. Sample chunks:
```
data: …"delta":{"content":"The"}…
data: …"delta":{"content":" moon"}…
data: …"delta":{"content":" hangs"}…
…
data: …"delta":{"content":" cr"}…
data: …"delta":{"content":"aters"}…
…
```

Tokens that split across word boundaries appear (e.g., `cr` + `aters`).
Diak's renderer must concatenate naively without trimming.

**Measured rate** (see Area 6): median inter-event gap ~18.5 ms,
worst-case bursts ~0.3 ms apart. 20–50 Hz dispatch frequency
sustained over the body of a streaming response.

### Scenario B — Tool-call invocation

Prompt: "Please read the file /tmp/sse_a_simple.sh and tell me
what it does. Use the read_file or filesystem tool." Evidence:
`evidence/sse_b_tool_call.txt` (384 lines).

```
data: {"id":"chatcmpl-…","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}

event: hermes.tool.progress
data: {"tool":"read_file","emoji":"📖","label":"/tmp/sse_a_simple.sh","toolCallId":"call_aV4DOarv4IKkWldQ220pKiK5","status":"running"}

event: hermes.tool.progress
data: {"tool":"read_file","toolCallId":"call_aV4DOarv4IKkWldQ220pKiK5","status":"completed"}

data: {"id":"chatcmpl-…","choices":[{"index":0,"delta":{"content":"\n\n/tmp"},"finish_reason":null}]}
…
data: [DONE]
```

**Critical findings:**

1. **No `delta.tool_calls` field anywhere.** The OpenAI-shaped
   chat.completion.chunk objects do NOT surface tool calls in the
   delta. (`grep -c "tool_calls" evidence/sse_b_tool_call.txt` →
   `0`.) Diak cannot reconstruct tool calls from the
   chat.completion.chunk stream alone.

2. **Tool events are out-of-band SSE events** using the
   `event:` named-event mechanism with payload type
   `hermes.tool.progress`. The `data:` line for these events is
   a Hermes-specific JSON shape, not a chat.completion.chunk.

3. **Two events per tool call:** `status: "running"` then
   `status: "completed"`. The `running` event carries
   `{tool, emoji, label, toolCallId}`; the `completed` event
   carries only `{tool, toolCallId, status}`.

4. **`tool_execution: server`** — by the time Diak observes
   `status: "running"`, the tool is *already running* on the
   server. There is no pre-execution hook.

5. **Tool output is NOT in the SSE stream.** The model's
   subsequent content deltas reference the tool's result, but the
   raw output is consumed server-side. Phase 3's tool-call card
   can show the *preview/label* and *status*, not the *result body*.

6. **Reasoning content is intermixed** in the post-tool deltas
   (e.g., `"\n\n/tmp"` + `"/s"` + `"se"` + ...) — the model
   simply continues generating after the tool completes.

The same logical sequence on `/v1/runs/{id}/events` (evidence:
`evidence/sse_runs_events.txt`) uses the cleaner native shape:
```
data: {"event":"tool.started","run_id":"run_…","timestamp":1778551556.013,"tool":"read_file","preview":"/tmp/sse_a_simple.sh"}

data: {"event":"tool.completed","run_id":"run_…","timestamp":1778551557.338,"tool":"read_file","duration":1.325,"error":false}
```

Note the **`duration` and `error` fields** on `tool.completed`
in the /v1/runs shape — absent from the /v1/chat/completions shape.

### Scenario C — Reasoning content

Prompt: "Think step by step: what is 47*23? Show your reasoning,
then give the final answer." Request includes
`"reasoning_effort": "high"`. Evidence:
`evidence/sse_c_reasoning.txt`.

```
event: hermes.tool.progress
data: {"tool":"terminal","emoji":"💻","label":"python3 - <<'PY' print(47*23) PY","toolCallId":"call_Vkjy4NkkPGIy2toHPtEtXjrS","status":"running"}

event: hermes.tool.progress
data: {"tool":"terminal","toolCallId":"call_Vkjy4NkkPGIy2toHPtEtXjrS","status":"completed"}

data: …"delta":{"content":"\n\n47"}…
data: …"delta":{"content":" ×"}…
…
```

**Findings:**

1. **`reasoning_effort: "high"` doesn't produce separate
   `reasoning` deltas** via `/v1/chat/completions`.
   `grep -c "reasoning" evidence/sse_c_reasoning.txt` → `0`.

2. **The model solved 47×23 by calling the `terminal` tool with
   `python3 - <<'PY' print(47*23) PY`** — a Python subprocess
   was spawned on the API server host to do basic arithmetic.
   This is `tool_execution: server` in action and underscores
   the **security implication**: server-side tools can execute
   arbitrary shell.

3. **Reasoning is post-hoc on `/v1/runs/{id}/events`.** The
   `reasoning.available` event fires *after* all message deltas
   and *before* `run.completed`, carrying a Hermes-generated
   summary string. Sample from `evidence/sse_runs_events.txt`:
   ```
   data: {"event":"reasoning.available","run_id":"…","timestamp":…,"text":"/tmp/sse_a_simple.sh is a small Bash script that sends a streaming OpenAI-compatible chat completion request to a local Hermes Agent API at http://127.0.0.1:8642/v1/chat/completions.\n\nIt uses a bearer token, asks the hermes-agent model to reply exactly “hello”, …"}
   ```
   This is a summary, not raw model-step traces. The session
   storage (`/api/sessions/{id}/messages` on dashboard) has
   richer `reasoning`, `reasoning_content`, `reasoning_details`,
   and `codex_reasoning_items` fields per Phase 1 REALITY but
   those are post-run records, not streamed.

### Scenario D — Mid-stream error / pre-stream error

Three sub-scenarios captured.

**D1 — invalid model name.** Evidence:
`evidence/sse_d1_invalid_model.txt`. Hermes **silently falls
back to default**: `model: "this-model-does-not-exist"` is echoed
in the response but the actual `hermes-agent` model is used. Not
a useful error trigger.

**D2 — malformed body (missing `messages`).** Evidence:
`evidence/sse_d2_malformed.txt`.
```
HTTP/1.1 400 Bad Request
Content-Type: application/json; charset=utf-8
Content-Length: 94

{"error":{"message":"Missing or invalid 'messages' field","type":"invalid_request_error"}}
```
Pre-stream JSON error body, standard HTTP 400. No SSE.

**D3 — bad auth.** Evidence captured inline (same Bash run):
```
HTTP/1.1 401 Unauthorized
{"error":{"message":"Invalid API key","type":"invalid_request_error","code":"invalid_api_key"}}
```

**Findings:**

- **Pre-stream errors are JSON-bodied 4xx HTTP responses**, not
  SSE error events. They arrive BEFORE `text/event-stream`
  content-type takes over.
- Diak's existing `HermesAPIServerClient` already handles 401
  via `ClientError.authenticationFailed` and 4xx via
  `ClientError.httpStatus`. No new error-event parser needed for
  pre-stream errors.
- **True mid-stream errors are rare on Hermes today.** No probe
  produced an in-stream error event. If the model rate-limits,
  the upstream provider returns 4xx synchronously and Hermes
  forwards it pre-stream. Phase 3 should still defensively
  handle "stream ends without `[DONE]` or `run.completed`" as a
  separate failure mode.

### Scenario E — Dropped connection

**E1 — server killed mid-stream.** Evidence:
`evidence/sse_e_dropped_connection.txt`. Protocol:
1. Started a long-generation request (1000-word essay).
2. Waited 3 s; captured 465 bytes (headers + role-only chunk).
3. `kill -9 <api_server_pid>` (PID 37056 → gateway killed).
4. curl exited with status 18: "transfer closed with outstanding
   read data remaining."

Last bytes captured before disconnect:
```
HTTP/1.1 200 OK
Content-Type: text/event-stream
Transfer-Encoding: chunked
…
data: {"id":"chatcmpl-…","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}

curl: (18) transfer closed with outstanding read data remaining
```

**Diak `URLSession.bytes(for:)` implication:** when the TCP
connection drops, the async byte iterator's `next()` throws an
`URLError` (typically `.networkConnectionLost` for an
established-then-dropped connection). Diak's existing SSE parser
in `HermesAPIServerClient.swift` wraps `bytes(for:)` already; the
thrown error will propagate through `AsyncThrowingStream`. WU3.5
should map dropped-connection to "stream interrupted; partial
content preserved."

**E2 — client cancel attempt.** Sent `kill -TERM` to the curl
pid after 2 s. Captured file
`evidence/sse_e2_client_drop.txt` (43,999 bytes, 201 content
deltas, includes `[DONE]`) shows the curl actually **finished
the stream** before SIGTERM took effect — the model called the
`terminal` tool (`seq 1 100`) which produces instant output, and
curl wrote the response to its redirected stdout faster than the
signal handler ran. Not a useful client-disconnect simulation
via curl. The Diak-side mechanism is different and well-defined:
`Task.cancel()` on the Task consuming the `AsyncThrowingStream`
from `bytes(for:)` aborts the iterator; the stream finishes with
a `CancellationError`. WU3.5 should verify this in a unit test
with a synthetic SSE source under `URLSession` mocking, since
cancelling against a live API is timing-dependent.

**E3 — gateway auto-respawn.** Within ~3 seconds of the kill,
Hermes' gateway respawned itself (new PID), and
`curl http://127.0.0.1:8642/health → 200`. Phase 3 reconnect
logic can rely on Hermes' self-supervision (no Diak-side
restart required for the API Server process), but DIAK must
re-establish the SSE connection — there is no state recovery
between runs (a new chat call is required; the partial response
is lost).

### Run-stop probe (relevant to Area 4)

Evidence: `evidence/sse_slow_tool_stop.txt`.

1. Started run with prompt: "Run this exact command in the
   terminal: sleep 10 && echo done."
2. Waited ~3.5 s for `tool.started` event.
3. Sent `POST /v1/runs/{id}/stop` 44 ms after `tool.started`.
4. `run.cancelled` event arrived 120 ms after `tool.started`,
   followed by `: stream closed`.

```
data: {"event":"tool.started","run_id":"run_…","timestamp":1778551869.942,"tool":"terminal","preview":"sleep 10 && echo done"}

data: {"event":"run.cancelled","run_id":"run_…","timestamp":1778551870.062}

: stream closed
```

**Diak can issue /stop within ~50 ms of `tool.started`.** Whether
the server-side tool *subprocess* actually dies on /stop (vs.
being orphaned) was not probed at the OS-process level; should be
verified during WU3.5 implementation. Even in the best case, fast
tools (filesystem rm, instant API POST) complete before /stop
arrives.

### Summary of SSE protocol surface area for Phase 3

The set of event shapes WU3.2-3.5 must render:

**From `/v1/chat/completions` (stream: true):**
- `data: {chat.completion.chunk with delta.role}` — first event
- `data: {chat.completion.chunk with delta.content: <token>}` —
  content stream
- `data: {chat.completion.chunk with delta: {}, finish_reason,
  usage}` — final
- `event: hermes.tool.progress\ndata: {tool, emoji?, label?,
  toolCallId, status: "running"}` — tool start
- `event: hermes.tool.progress\ndata: {tool, toolCallId,
  status: "completed"}` — tool end
- `data: [DONE]` — terminator

**From `/v1/runs/{id}/events`:**
- `data: {event: "tool.started", run_id, timestamp, tool,
  preview}`
- `data: {event: "tool.completed", run_id, timestamp, tool,
  duration, error}`
- `data: {event: "message.delta", run_id, timestamp, delta:
  "<token>"}`
- `data: {event: "reasoning.available", run_id, timestamp, text}`
- `data: {event: "run.completed", run_id, timestamp, output,
  usage}`
- `data: {event: "run.cancelled", run_id, timestamp}`
- `: stream closed` — SSE comment, terminator

**Recommendation for SCOPE.md:** Phase 3 should standardize on
`/v1/runs/{id}/events` for the streaming surface. Cleaner event
shape, richer tool metadata (duration, error flag), native
reasoning event, explicit run.completed terminator, and the
`/v1/runs/{id}/stop` companion is required for the approval flow
in Area 4. The Phase 1 SCOPE used `/v1/chat/completions` for
simplicity; Phase 3 inherits a richer protocol need.

## Investigation Area 2 — Swift markdown library evaluation

Three candidates compared. Full agent report in this run's
conversation transcript; condensed findings:

### Down (`johnxnguyen/Down`)

- **Install:** SwiftPM `https://github.com/johnxnguyen/Down`,
  latest tag `0.11.0`. Vendors cmark 0.29.
- **License:** MIT.
- **Maintenance:** **Abandoned.** Last commit `e754ab1` on
  2021-10-18 (4.5 years stale); 45 open issues including recent
  breakage (#311 "Unable to find libcmark dependency",
  2025-09-29).
- **Streaming:** No streaming API.
- **Half-fence handling:** Safe per CommonMark §4.5 — unclosed
  fence renders as a `CodeBlock` containing body to EOF; cmark
  guarantees no crash.
- **SwiftUI:** None. Outputs `NSAttributedString` or
  `WKWebView` via `DownView`. Issue #231 "SwiftUI support"
  closed unresolved.
- **Verdict:** Disqualified by maintenance + WKWebView render
  cost at streaming frequencies.

### MarkdownUI (`gonzalezreal/swift-markdown-ui`)

- **Install:** SwiftPM, latest tag `2.4.1` (2024-10-13).
  Transitive: `swiftlang/swift-cmark` + `gonzalezreal/NetworkImage`.
- **License:** MIT.
- **Maintenance:** **Maintenance mode declared 2025-12-28** —
  last commit literally updates README to point users at
  successor `gonzalezreal/textual`. 60 open issues including
  performance-critical #426 (full app freeze on long markdown)
  and crash #396 (EXC_BAD_ACCESS on long code blocks with
  syntax highlighting on iOS).
- **Streaming:** No streaming API. Discussion #261 confirms
  per-chunk full re-parse — unfixable from outside.
- **Half-fence handling:** Safe (same cmark-gfm backing).
- **SwiftUI:** **Native SwiftUI Views.** `Markdown("…")` is a
  drop-in View; rich theming.
- **Verdict:** SwiftUI ergonomics are real but disqualified by
  maintenance-mode status + documented freeze cliffs on streaming
  workload.

### swift-markdown (`apple/swift-markdown`)

- **Install:** SwiftPM `https://github.com/swiftlang/swift-markdown.git`
  on `branch: "main"` (Apple's README recommends branch over
  tags). swift-tools-version 6.2. Transitive: `swift-cmark`
  (cmark-gfm), `CAtomic`.
- **License:** Apache-2.0 with Runtime Library Exception.
- **Maintenance:** **Actively maintained by Apple.** Last commit
  `ba1fbd1b` on 2026-05-07 (5 days before this investigation).
  Stable `0.8.0` shipped 2026-05-07.
- **Streaming:** No streaming API per se, but **AST-based**: a
  `Document(parsing: source)` produces a tree of `BlockMarkup` /
  `InlineMarkup` values. Cheap to re-parse; expensive part of
  rendering is SwiftUI diff.
- **Half-fence handling:** Safe (same cmark-gfm backing).
- **SwiftUI:** **None.** Pure AST. Custom renderer required
  (visitor pattern over `Markup` protocols → SwiftUI views).
  Cost: ~200–400 LOC for a renderer covering paragraphs,
  headings, lists, code blocks (Splash for highlighting), tables,
  blockquotes, inline emphasis/code/links.
- **Verdict:** **Picked for Diak.**

### Recommendation: swift-markdown + hand-written SwiftUI renderer

Rationale:

1. **Streaming jank control.** The hard problem for streaming
   markdown isn't parse cost — cmark is fast. It's SwiftUI's
   view-diff cost when the entire rendered document re-evaluates
   per chunk. With an AST, Diak renders each top-level block
   (heading, paragraph, code block, table) as its own
   `Identifiable` SwiftUI View. Only the *last* block — the one
   being streamed into — re-renders per chunk; earlier blocks
   stay stable, and SwiftUI's diffing skips them. MarkdownUI
   can't do this because it owns the View construction; Down
   can't do this at all (WKWebView/NSAttributedString are
   monolithic).

2. **Half-fence correctness is free.** CommonMark §4.5 guarantees
   open fences render as code blocks. All three candidates inherit
   this from cmark, so we don't pay the half-fence-test cost
   regardless of pick.

3. **Maintenance.** Apple project, weekly commits, tracks the
   Swift toolchain. The other two are stale/deprecated.

4. **SwiftUI ergonomics.** No worse than MarkdownUI once the
   visitor exists — each block returns a `View`, you put them
   in a `LazyVStack`. The "no built-in renderer" cost is a
   one-time write of a focused renderer that Phase 3 owns.

**SCOPE commitment proposed:** Add
`.package(url: "https://github.com/swiftlang/swift-markdown.git",
branch: "main")` to `project.yml` as a Phase 3 dependency. Write
`HermesDesktop/Features/Chat/MarkdownRenderer/` with
`MarkdownDocumentView`, a `MarkupVisitor` → `View` adapter, and
block-level identity so SwiftUI's diff scope stays minimal.

## Investigation Area 3 — Existing Diak chat composer architecture

Post-Phase-1/2 chat code path, walked end-to-end. Source-line
references throughout.

### Composer state ownership

`HermesDesktop/Features/Chat/ChatViewModel.swift`. Properties:

```swift
@Published public private(set) var session: HermesSession?
@Published public private(set) var messages: [HermesMessage] = []
@Published public private(set) var phase: Phase = .idle
@Published public var draft: String = ""

private let sessionStore: DiakSessionStore?
private let apiServerClient: HermesAPIServerClient?
private let model: String
private var currentDiakSession: DiakSession?
private var streamTask: Task<Void, Never>?
```

Owned at `ContentRouter.swift:20` (`@StateObject private var chat:
ChatViewModel`), constructed with `sessionStore` +
`apiServerClient`. Lifetime is the App's WindowGroup; there's one
ChatViewModel per window.

### Send flow (current — non-streaming chat completion)

`ChatViewModel.startStreaming()` at lines 117–225. Six phases:

1. **Trim + clear draft** (lines 118–120).
2. **Lazy DiakSession creation** (lines 124–143). If
   `currentDiakSession == nil` and `sessionStore` is wired:
   `try store.createSession(title:, model:)`. Otherwise: offline
   path (no persistence; placeholder reply).
3. **Persist user message** to SwiftData (lines 146–158):
   `try sessionStore.addMessage(to: diakSession, role: "user",
   content: prompt, status: .complete)`. Surfaced to the view as a
   legacy-shaped `HermesMessage` via `appendToView(_:)` (line
   246).
4. **Synthesize a HermesSession view-shape** for header
   rendering (lines 161–171). One-way projection from Diak
   internals into the legacy view types.
5. **Send to API Server** (lines 173–195):
   `let response = try await apiServerClient.chatCompletion(request)`.
   The current request shape uses `ChatCompletionRequest` with
   *no streaming flag set*. The chat completion is non-streaming
   — Diak waits for the full response, parses
   `response.choices.first?.message.content`, and persists +
   surfaces as a single assistant message.
6. **Phase transitions** (lines 121, 185, 204, 222): `idle →
   starting → streaming → completed | failed(reason)`.

### Persistence layer

`DiakSessionStore.attach(hermesState:)` (Phase 2 WU2.4-D) wires
the store to dispatch `.diakSessionCreated(uuid)` /
`.diakSessionDeleted(uuid)` to HermesState on the same main-actor
cycle as `try context.save()`. Currently `addMessage` does NOT
dispatch a per-message action — the reducer has no message slice
in Phase 2 (per SCOPE).

### View layer

Three SwiftUI views consume `ChatViewModel`:
- `ChatRootView.swift:7` — top-level chat surface.
- `ChatTranscriptView.swift:6` — message list + composer.
- `HomeNewChatView.swift:8` — empty-state new-chat composer.

`ChatTranscriptView` renders messages via
`MessageBlock(message:)` inside a `LazyVStack` inside a
`ScrollViewReader` → `ScrollView`, with auto-scroll on
`onChange(of: viewModel.messages.last?.id)` (line 62) and
`onChange(of: viewModel.messages.last?.content)` (line 67). The
content-change observer is important: it already triggers
re-scroll on every chunk update, which means Phase 3 streaming
will scroll-track automatically *if* the streaming message's
content is dispatched to the same `@Published var messages`
array.

### Legacy types still in play

The view-side types (`HermesMessage`, `HermesSession`,
`HermesStreamEvent`) survive from Phase 0 even though Diak's
storage uses `DiakMessage`, `DiakSession`, `DiakRun`. The
view-model is the boundary; it projects Diak's SwiftData rows
into legacy view shapes for the views.

`HermesStreamEvent` exists but is unused — `ChatViewModel.apply(_:)`
at lines 237–242 is a no-op shim kept for back-compat with
legacy tests. Phase 3 will revive this surface (or replace it
with a new event shape).

### Implications for Phase 3 WU3.3 (chat rewiring)

The current architecture has a clean seam for streaming:

- **Persistence already lives in DiakSessionStore.** Streaming
  writes can land in `DiakMessage.content` with
  `status: .streaming`, then flip to `.complete` on `[DONE]` /
  `run.completed`.
- **The composer's content-change observer already does
  auto-scroll** on `messages.last?.content`. A streaming
  message that re-publishes its `content` per token will
  scroll-follow without changes.
- **The `HermesAPIServerClient.runEvents(runId:)`
  `AsyncThrowingStream<RunEvent, Error>` API already exists**
  (lines 131–) from Phase 1 WU4. It's currently unconsumed in
  production but tested live. WU3.3 wires
  `startStreaming()` to use it via `startRun` + `runEvents`.
- **The phase enum already includes `.streaming`**; Phase 3
  doesn't need new top-level phases.
- **The legacy `HermesStreamEvent` apply() shim** is the natural
  hook to retire / replace with the Phase 3 event-pump entry
  point.

The migration ladder:
1. Add `currentStream: StreamingMessageState?` to ChatViewModel
   (see Area 6).
2. In `startStreaming()`, replace the
   `chatCompletion(non-streaming)` call with `startRun +
   runEvents` consumption.
3. As each `message.delta` event arrives, append to
   `currentStream.content` (no HermesState dispatch — see Area 6).
4. On `tool.started` / `tool.completed`, append to
   `currentStream.toolEvents` for inline rendering.
5. On `run.completed`: persist the final message to
   `DiakSessionStore` (triggers existing `.diakSessionUpdated`-
   style dispatch), set `currentStream = nil`, set phase to
   `.completed`.

No new "where does state live" decision; Phase 3 fits the existing
geography.

## Investigation Area 4 — Approval flow protocol

Cited Pattern (a), (b), (c) from Nick's WU3.1 brief. Each
evaluated against the captured protocol surface.

### Pattern (a) — Client-side gating via stream termination

**Plan:** Diak intercepts `tool.started` events. On first such
event, Diak issues `POST /v1/runs/{id}/stop`. Diak prompts user
for approve/deny. On approve: Diak re-runs from scratch with the
prior context plus a system note that the tool is approved.

**What the API supports (verified live):**
- `POST /v1/runs/{id}/stop` returns `{run_id, status:"stopping"}`
  synchronously. The events stream gets a `run.cancelled` event
  then closes (`evidence/sse_slow_tool_stop.txt`).
- Latency from `tool.started` to `run.cancelled`: ~120 ms in
  the slow-tool probe (44 ms client-side delay before sending
  /stop + 76 ms server roundtrip).

**What the API does NOT support:**
- **No native pause/resume.** The /stop endpoint cancels; no
  /resume. To "approve" a previously denied tool, Diak must
  start a new run with the conversation history reconstructed.
- **No injectable "tool X is approved" context.** Diak would
  have to fabricate this via a system message or a
  `tool` role message — the model's behavior under these
  injections is best-effort.
- **No interlock between `tool.started` and tool execution.**
  The server has already invoked the tool by the time it emits
  the event. For fast tools (<50 ms), Diak's /stop arrives too
  late.

**Verdict:** *Best-effort* gating only. Workable for slow tools
(file writes, network requests, sleeps); useless for instant
tools (filesystem rm, in-memory state). Doubles inference cost
(every gated tool requires a re-run).

### Pattern (b) — Tool-level wrapping

**Plan:** Diak presents wrapper tools to Hermes via OpenAI-style
`tools` parameter. Wrappers' implementation calls back to Diak
for user approval before forwarding to the real tool.

**What the API supports:**
- Hermes' API Server is OpenAI-compatible, so a request body can
  include `tools` and `tool_choice` parameters.
- BUT: `runtime.tool_execution: "server"` per capabilities — the
  server uses its own `agent.toolsets: ["hermes-cli"]` config.
  Diak's tools-array on the request likely gets ignored or
  conflicts with Hermes' server-side toolset (untested; not in
  scope for this WU but should be probed in WU3.5 if Pattern (b)
  is reconsidered).
- For Diak's wrappers to call back, Hermes would need a callback
  URL to Diak — which doesn't exist via the API Server.

**Reality check:** Hermes' approval config (`evidence`-equivalent:
`/api/config` returns `"approvals": {"mode": "manual", "timeout":
60, "cron_mode": "deny", "mcp_reload_confirm": true}`) suggests
the **native approval mechanism exists** but is **not wired into
the API Server.** Source check:
`grep -n "approval" gateway/platforms/api_server.py` returns
nothing. The approval callback machinery in `run_agent.py` (lines
119, 121, 3668–3680, 9904–9981) handles CLI-context approvals
via `set_approval_callback(callable)`, but `api_server.py` never
sets one. **API-Server requests effectively run in "approve
everything" mode regardless of `approvals.mode`.**

**Verdict:** Cannot implement Pattern (b) without modifying
Hermes' API Server (out of scope — Hermes is a separate project
Diak vendors). Phase 4 could explore Diak-as-MCP-server (Hermes
supports MCP toolsets per `mcp_servers` config) where Diak owns
the execution side, but that's a different work unit.

### Pattern (c) — Request-level interception with resume

**Plan:** Same as (a) but with resume rather than re-run from
scratch.

**What the API supports:** Nothing. No resume endpoint exists.
The capabilities probe shows the run-control surface is
`POST /v1/runs`, `GET /v1/runs/{id}`, `GET /v1/runs/{id}/events`,
`POST /v1/runs/{id}/stop`. No `POST /v1/runs/{id}/resume`.

**Verdict:** Not implementable on the current API.

### Native Hermes "approvals" config — does it bind to API Server?

`/api/config` reports:
```json
"approvals": {
  "mode": "manual",
  "timeout": 60,
  "cron_mode": "deny",
  "mcp_reload_confirm": true
}
```

But `gateway/platforms/api_server.py` contains **zero references
to approval callbacks**. The approval callback machinery in
`run_agent.py` is wired for interactive CLI sessions and the
TUI; it is not registered for API Server requests. Live
verification: Scenario B above ran tool `read_file` against my
live API Server without prompting for approval, despite
`approvals.mode: "manual"` being set.

**Conclusion:** Diak cannot rely on Hermes-side approvals for
API Server-driven chat. Diak owns the approval surface
end-to-end (consistent with Decision #13 — "Diak owns
approvals").

### Recommended Phase 3 approval pattern: A-modified ("Best-Effort Stop")

```
┌────────────────────────────────────────────────────────────┐
│ User sends prompt with "Require approval" mode enabled.    │
└────────────────────────────────────────────────────────────┘
                            │
                            ▼
       Diak: POST /v1/runs with prompt + history
                            │
                            ▼
       Diak: GET /v1/runs/{id}/events (streaming)
                            │
                            ▼
       For each event:
         - message.delta → append to streamingContent
         - tool.started → ┐
                          ▼
                  ┌────────────────────────────────────┐
                  │ FIRE: POST /v1/runs/{id}/stop       │
                  │ (parallel; race against tool)       │
                  │                                     │
                  │ Surface approval prompt to user:    │
                  │   - tool name                       │
                  │   - preview (label/arguments)       │
                  │   - "Approve" / "Deny" / "Always"   │
                  └────────────────────────────────────┘
                          │
                          ▼
         - tool.completed → tool ran before /stop arrived
            ⇒ mark as "Already executed" + log for audit
         - run.cancelled → /stop won the race
            ⇒ wait for user decision; act:
              · Approve → start new run with original prompt
                          + "Tool X was approved; proceed"
                          system note. Replay conversation
                          history from DiakSessionStore.
              · Deny    → start new run with "Tool X was
                          denied; respond without using it"
                          system note.
```

**Acceptance criteria for Phase 3 SCOPE:**

1. Approval mode is **opt-in per-session** (default: off; matches
   Hermes' default behavior so we don't surprise the user).
2. Tools faster than the /stop roundtrip are surfaced as
   "Already executed: <tool>" with the action permanently
   recorded in the session log. UX: yellow warning, not red error
   — the user knows about it but the tool already happened.
3. Approved/denied tools result in a **re-run from scratch**
   with conversation history replay. Cost: ~2× inference for
   gated turns. Tradeoff documented and exposed in settings.
4. Diak owns the approval record (Decision #13). Each approval
   stored in `DiakSessionStore` keyed by `toolCallId` so the
   inspector can show approval history per session.

### What Phase 4 should consider (out of Phase 3 scope)

- **Diak-as-MCP-server** giving Diak deterministic gating on a
  Diak-owned subset of tools. Requires Hermes' `mcp_servers`
  config edit (Phase 4 territory). With MCP, Diak controls
  tool execution itself — true pre-execution approval is
  achievable. Phase 3's "best-effort stop" pattern becomes the
  fallback path for non-MCP tools.
- **Per-tool autonomy levels.** Some tools (read_file) can
  default to auto-approve; others (terminal, file writes) get
  manual review. Diak-side config; doesn't require Hermes
  changes.

## Investigation Area 5 — Tool-call card rendering precedent

Four references surveyed. Hermes' own dashboard source is at
`/Users/perlantir/.hermes/hermes-agent/web/src/components/ToolCall.tsx`
(lines 22–175) and `ChatSidebar.tsx` (lines 198–372).

### Cursor (IDE chat sidebar)

- **Visual:** Inline rows with tool-type icon + tool name + target
  (file path / command / query). For `edit_file`, the diff renders
  inline as part of the row. Collapsible; "compact mode" added in
  Cursor 1.4.
- **Info shown:** Icon, target/arg summary, diff body, truncated
  terminal output. No explicit duration badge.
- **Position:** **Interleaved** with assistant text — diffs and
  paths appear in turn, model resumes "at the next ideal time."
- **Status:** Streaming activity indicator while running; static
  rows once complete.
- **Expand:** Click-to-expand for diffs and terminal output;
  compact mode collapses by default.
- **Source:** [Cursor 1.4 changelog](https://cursor.com/changelog/1-4),
  [3.0 changelog](https://cursor.com/changelog/3-0),
  [Agent overview](https://cursor.com/docs/agent/overview).

### Claude.ai (web)

- **Visual:** Status-text line ("Searching the web…",
  "Read [filename]") that resolves to an expandable section once
  complete. Research mode produces multi-step collapsible traces.
- **Info shown:** Activity label, inline citations linking to
  sources for web search. No duration badge.
- **Position:** **Interleaved** — appears where the model called
  the tool, followed by the model's text continuation.
- **Status:** Animated label while running, past-tense label
  once done.
- **Expand:** Click to expand queries/sources/steps; citations
  stay inline in answer text after collapse.
- **Source:** [Claude Web Search help](https://support.claude.com/en/articles/10684626-enabling-and-using-web-search),
  [Using Research on Claude](https://support.claude.com/en/articles/11088861-using-research-on-claude).

### ChatGPT (web)

- **Visual:** Inline card with app/tool name + icon. Apps SDK
  defines this as "a lightweight, single-purpose widget embedded
  directly in conversation," with title, icon, content area, up
  to two primary actions, optional fullscreen-expand. Built-in
  tools show "Analyzing…" / "Searched 5 sites" status text that
  expands to a step list.
- **Info shown:** Tool/app name + icon, status text, content
  (chart/code/citations), action buttons. Code interpreter shows
  the Python in a collapsible block.
- **Position:** **Interleaved with a fixed rule** — Apps SDK
  docs state "inline surfaces currently always appear before the
  generated model response." Tool widget renders, then the
  assistant message that consumes it follows.
- **Status:** Composer "shimmers" during streaming;
  "Analyzing…" / "Thinking…" labels while running; past-tense
  resolution when done. SDK exposes
  `openai/toolInvocation/invoking` and `…/invoked` metadata.
- **Expand:** Click to expand code, step list, or fullscreen.
- **Source:** [Apps SDK UI Guidelines](https://developers.openai.com/apps-sdk/concepts/ui-guidelines),
  [Apps SDK Build Guide](https://developers.openai.com/apps-sdk/build/chatgpt-ui).

### Hermes Dashboard (read from source)

- **Visual:** Collapsible bordered row in `ToolCall.tsx`. Format:
  `▸ ⚡ tool_name(context)  [status icon]  [elapsed]`. Errors
  auto-expand; others collapsed by default. Background color
  shifts by status (`bg-primary/[0.04]` running, `bg-muted/20`
  done, `bg-destructive/[0.04]` error).
- **Info shown:** Tool name (mono), context string (arg preview
  like `path=/foo`), elapsed time (live-tickers every 500 ms
  while running, formatted ms→s→m). On expand: `context`,
  `preview` (streaming buffer with cursor caret), `inline_diff`
  (+/- colorized), `summary`, `error`.
- **Position:** **Grouped separately** — tool rows live in a
  dedicated "tools" Card in the right sidebar
  (`ChatSidebar.tsx`), NOT interleaved with assistant text. The
  TUI pane handles text independently. Capped at `TOOL_LIMIT`
  (most recent N).
- **Status:** Pulsing primary-color dot while running, `Check`
  icon on done, `AlertCircle` on error. The `Zap` bullet on
  the left recolors by status.
- **Expand:** Chevron toggle; user override is tri-state
  (`null | true | false`) so errors auto-expand without locking
  the user out of collapsing them.

### Convergent patterns across all four

1. **Three status states** — running / done / error — universally
   rendered with distinct visual treatment (animated → checkmark
   → alert).
2. **Tool name + brief arg preview is the row's primary content.**
   Full structured arguments are expandable, not default-visible.
3. **Default collapsed, errors auto-expand.** All four converge.
4. **Live progress indicator during running state.** Whether it's
   a pulsing dot (Hermes), an animated label (Claude/ChatGPT), or
   composer shimmer (ChatGPT), no product shows a static "running"
   state — the user gets continuous feedback.
5. **Position is product-dependent.** Cursor/Claude/ChatGPT
   interleave; Hermes sidebar-groups. Both are valid UX choices
   driven by the product's surface area.

### Recommendation for Diak

**Adopt Hermes' `ToolCall.tsx` row pattern; interleave with
assistant text (Cursor/Claude/ChatGPT-style) rather than
sidebar-group.**

Reasoning anchored to Diak's actual data shape:

1. **The three-state model maps 1:1 to our SSE event pair.**
   Hermes' dashboard component already implements running / done /
   error transitions driven by the same events Diak will consume
   (`tool.started` → running, `tool.completed` with `error: false`
   → done, `tool.completed` with `error: true` → error).
   Live-ticking elapsed counter (Hermes' lines 63–67) is the right
   answer for the running window — duration-on-completion alone
   doesn't feel responsive.

2. **We only have what we have.** Diak's available fields from
   `/v1/runs/{id}/events`:
   - `tool.started`: `{tool, preview, run_id, timestamp,
     toolCallId}` — name + arg summary
   - `tool.completed`: `{tool, duration, error, run_id,
     timestamp}` — duration + error flag

   We do NOT receive `summary`, `inline_diff`, `preview` body, or
   raw tool output via SSE. Hermes' dashboard gets richer payloads
   because it's a dashboard plugin with internal API access. The
   Diak row's expanded body should show ONLY what we actually
   have: `tool` + `preview` text + on error the error indication.
   Don't build an expandable section that promises full args /
   results we can't deliver. Match Hermes'
   `disabled={!hasBody}` discipline (line 93) — non-expandable
   when there's nothing to show.

3. **Interleave rather than sidebar.** Hermes parks tool rows in
   a sidebar because the TUI pane is the primary text surface.
   Diak is a SwiftUI chat surface where the message list IS the
   product. Cursor / Claude.ai / ChatGPT all interleave; that
   matches user expectation for a chat product. ChatGPT's Apps
   SDK ordering rule ("inline surfaces appear before the
   generated model response") is the right pattern: render the
   tool row as its own message-list item slotted in turn order,
   then the assistant continuation bubble appears after.

4. **Default collapsed; errors auto-expand.** Universal across
   all four references. Port Hermes' `userOverride ?? error`
   idiom to SwiftUI as `@State private var userOverride: Bool? = nil`
   with effective expansion = `userOverride ?? isError`.

5. **Status indicators, not full badges.** Hermes' single-glyph
   approach (pulsing dot / check / alert-circle) fits macOS
   aesthetics better than ChatGPT's heavier widget cards.
   SF Symbols: `circle.fill` (with opacity-pulse animation for
   running), `checkmark`, `exclamationmark.triangle.fill`.

### Concrete shape for the Diak tool-call card

```
⚡ read_file   /tmp/sse_a_simple.sh          ● 1.3s
```

- Pulsing dot during running, swaps to checkmark on completion,
  to alert-triangle on error.
- Row sits in the chat message list as its own list item between
  assistant bubbles, identified by `toolCallId` for stable
  SwiftUI identity.
- Tap-to-expand only when `preview` text exists; expanded view
  shows `args: <preview>` and nothing else.
- Errors auto-expand and show the error indication.
- Live duration counter while in running state (500 ms refresh
  matching Hermes' implementation).

### Source paths (for WU3.4 implementation reference)

- `~/.hermes/hermes-agent/web/src/components/ToolCall.tsx` —
  the canonical component (Hermes dashboard). Translate the
  layout structure to SwiftUI; don't port the data model
  wholesale because our fields are sparser.
- `~/.hermes/hermes-agent/web/src/components/ChatSidebar.tsx`
  (lines 198–266) — wires `tool.start`/`tool.progress`/
  `tool.complete` events to component state. Reference for the
  event-handler logic Diak's view-model must replicate.

## Investigation Area 6 — Multi-window propagation during streaming

### Measured streaming rate

Probe: 50-fruit list prompt, captured 136 content-delta chunks
in 6.73 s.

- Sustained rate: **~20 chunks/sec**.
- Median inter-event gap (on /v1/runs): **18.5 ms** (~54 Hz peak).
- Min gap: 0.3 ms (back-to-back tokens within burst).
- 48 of 87 events had <20 ms gap = consecutive bursts within one
  frame budget.

### What happens if streaming token deltas go through the Phase 2 reducer

`HermesState.dispatch(_:)` cost per call:
- `currentSnapshot()` builds a value-type snapshot copying every
  `@Published` property's current value (13 properties in
  Phase 2's shape).
- `HermesReducer.reduce(snapshot, action)` runs the pure reducer.
- Snapshot equality check: `newSnapshot != oldSnapshot` deep-
  compares all 13 fields via Equatable.
- If different, `apply(snapshot)` walks each field with "set if
  different" and emits `@Published.willSet`/`didSet`.

For a streaming message dispatched per-token:
- The snapshot would grow per chunk (chat message content
  appended). String equality is O(n) where n is message length.
- Over a 500-token response, equality comparison alone is
  O(n²) total work.
- Every Combine subscriber on the relevant `@Published`
  property re-fires per chunk.
- SwiftUI diffs the entire view tree downstream.

At 50 Hz on multi-KB messages, this likely produces observable
lag and undermines Phase 2's 2 s multi-window SLA
(`MultiWindowPropagationTests.testDispatch_FromOneSkillsVM_…`
proved 2 s for coarse-grained slices; per-token dispatch is a
different magnitude).

### Recommended pattern: fast-lane streaming state, separate from reducer

**Architecture:**

```
┌──────────────────────────────────────────────────────────┐
│ HermesState  (canonical; coarse-grained)                 │
│ - diakSessions: [UUID]                                   │
│ - dashboard, skills, config, ...                         │
│ - NEW (Phase 3): no per-token actions                    │
└──────────────────────────────────────────────────────────┘
                              ▲
                              │ .diakSessionUpdated / final
                              │ message persisted
                              │
┌──────────────────────────────────────────────────────────┐
│ ChatViewModel  (window-local; owns one stream at a time) │
│ @Published currentStream: StreamingMessageState?         │
│ ...                                                      │
└──────────────────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │ StreamingMessageState                   │
        │ @Published content: String              │
        │ @Published toolEvents: [ToolEventDisplay]│
        │ @Published phase: .running | .completed │
        └─────────────────────────────────────────┘
                              ▲
                              │ append on each
                              │ message.delta /
                              │ tool.* event
        ┌─────────────────────────────────────────┐
        │ HermesAPIServerClient.runEvents(runId:) │
        │  AsyncThrowingStream<RunEvent, Error>   │
        └─────────────────────────────────────────┘
```

**Flow:**

1. `ChatViewModel.startStreaming()` creates a new
   `StreamingMessageState`, sets `currentStream = state`.
2. Subscribes to `runEvents(runId:)`. On each event, updates
   `state.content` / `state.toolEvents` — these emissions are
   local to `state`, no HermesState dispatch.
3. The view binds to `currentStream?.content` for the in-flight
   message. SwiftUI re-renders the streaming message only.
4. On `run.completed`:
   - Persist final content to `DiakSessionStore.addMessage(...)`
   - That triggers `DiakSessionStore` → `HermesState.dispatch`
     for the coarse "session updated" action (Phase 3 may add
     `.diakMessageAppended(sessionID, messageID)` if needed for
     multi-window propagation of completion).
   - Set `currentStream = nil`.

**Multi-window implication:**

- If two windows both render the same `DiakSession`, only the
  window with the active `ChatViewModel.currentStream` shows the
  streaming response.
- The other window sees the final message appear once
  `run.completed` lands and the store dispatches its action.
- This matches reasonable UX: "I'm typing in window A; window B
  sees results when they're done."
- If we want both windows to see the live stream, that requires
  sharing the `StreamingMessageState` via a higher-up
  `@StateObject` and adding the streaming state to HermesState.
  Phase 3 should NOT do this — multi-window-live-stream is a
  Phase 6+ polish concern, not a v1 requirement.

### Why this isn't a Phase 2 architectural violation

Phase 2's reducer was designed for **observably distinct**
state — slices that the UI renders, that polling updates, that
multiple subscribers care about. Streaming tokens fail both
"observably distinct" (intermediate tokens are display-only;
nobody persists "token 47 of 500") and "multiple subscribers
care" (only the one composer view cares).

Phase 2 SCOPE.md anticipated this: "Phase 3 may extend
[HermesAction] if they add polling for additional endpoints."
Phase 3 explicitly does NOT extend with per-token actions; it
adds parallel state. This is consistent with the reducer's
purpose (canonical mutations) versus per-view ephemeral state.

### What Phase 3 SCOPE.md should commit to

1. Introduce `StreamingMessageState` in
   `HermesDesktop/Features/Chat/StreamingMessageState.swift`.
2. `ChatViewModel.currentStream: StreamingMessageState?` is the
   live-stream pointer; `nil` between turns.
3. Add `HermesAction.diakMessageAppended(sessionID: UUID,
   messageID: UUID)` to the reducer for completion-time
   cross-window propagation (NOT per-token).
4. Document the per-token "fast lane" + completion "slow lane"
   distinction in the Chat module's README so future work units
   don't re-invent.

## Summary of WU3.1 findings (one-line each)

1. **Two SSE surfaces, different shapes** — Phase 3 should use
   `/v1/runs/{id}/events` (cleaner, richer, has /stop).
2. **No `delta.tool_calls`** — tool events arrive as out-of-band
   `event: hermes.tool.progress` (chat completions) or in-band
   `event: tool.started/completed` (runs API).
3. **`tool_execution: "server"`** — tools run on the API Server
   host without a Diak hook. Hermes' `approvals.mode: manual`
   is not wired through API Server.
4. **Token streaming sustained at 20-50 Hz** — too fast for
   Phase 2's reducer; needs a parallel fast-lane state.
5. **`/v1/runs/{id}/stop` works synchronously** — ~120 ms
   roundtrip from `tool.started`. Usable for slow tools, racy
   for instant ones.
6. **Dropped connection surfaces as `URLError`** through
   `URLSession.bytes`; Hermes' gateway auto-respawns; no Diak
   process recovery needed.
7. **Library pick:** `apple/swift-markdown` + hand-written
   SwiftUI renderer. Down and MarkdownUI both disqualified
   (abandoned / maintenance-mode + crash cliffs).
8. **Approval pattern:** "Best-Effort Stop" (Pattern A-modified)
   — opt-in, race /stop against tool, "Already Executed" UX for
   fast tools. True pre-execution gating deferred to Phase 4
   via Diak-as-MCP-server.
9. **Tool-call card pattern:** Hermes-dashboard row layout
   (`tool name | preview | status dot | live elapsed`) but
   interleaved with assistant text (Cursor/Claude/ChatGPT style).
   Single-glyph status indicators, default collapsed,
   errors auto-expand. Field set scoped to what
   `/v1/runs/{id}/events` actually delivers.
10. **Streaming state lives outside the reducer** — per-window
    `StreamingMessageState`; only completion-time events
    dispatch to HermesState. Multi-window during streaming is
    one-window-only by design.

## Evidence Index

All files in `Docs/Phases/Phase3/evidence/`:

| File | Contents |
|---|---|
| `api_server_capabilities.json` | Live `/v1/capabilities` response |
| `sse_a_simple_text.txt` | Scenario A: simple text streaming |
| `sse_a2_longer_text.txt` | Scenario A2: longer text (per-token chunks) |
| `sse_b_tool_call.txt` | Scenario B: tool call via /v1/chat/completions |
| `sse_c_reasoning.txt` | Scenario C: reasoning effort + auto-tool-use |
| `sse_d1_invalid_model.txt` | Scenario D1: invalid model silently fell back |
| `sse_d2_malformed.txt` | Scenario D2: pre-stream 400 error |
| `sse_e_dropped_connection.txt` | Scenario E: server-side kill mid-stream |
| `sse_e2_client_drop.txt` | Scenario E2: client-side SIGTERM mid-stream |
| `sse_runs_events.txt` | /v1/runs SSE shape — tool/message/reasoning/completed events |
| `sse_runs_submit_response.json` | POST /v1/runs response shape |
| `sse_runs_stop_test.txt` | /v1/runs stop probe — first attempt |
| `sse_slow_tool_stop.txt` | /v1/runs stop probe with slow tool — measured /stop latency |

Probe scripts are in `/tmp/sse_*.sh` (not committed; transient).
