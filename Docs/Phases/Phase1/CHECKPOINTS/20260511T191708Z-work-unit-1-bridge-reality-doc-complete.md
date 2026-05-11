# Phase 1 Work Unit 1 — Bridge Reality Doc — Completion Checkpoint

## Stopped At

2026-05-11T19:17:08Z (UTC)

## Stop Condition

Condition 1: Current commit's (work unit's) acceptance criteria met. Work
Unit 1's acceptance per SCOPE.md is "doc exists, every bridge endpoint is
captured with a reference to the source line that implements it, every
Diak Swift call site that hits the bridge is enumerated." All three are
satisfied. Per SCOPE.md "When complete: write checkpoint, push to phase
branch, stop. Nick ratifies before Work Unit 2 begins."

Several substantive Phase 1 scope concerns surfaced during the
investigation — flagged in Questions for Nick below per CLAUDE.md
Prohibition #11 ("Never expand the scope of the current phase. If a
needed change falls outside the current phase's SCOPE.md, stop and
checkpoint.") and SCOPE.md "What to Do If Any Work Unit Surfaces a
Surprise."

## Work Completed Since Last Checkpoint

Created `phase/1-hermes-runtime-integration` from main@560693a. Read the
canonical bridge (`archive/bridge-experiment:Scripts/diak_hermes_bridge.py`,
1475 lines) end-to-end. Read the unauthorized WIP delta
(`d7acf33:Scripts/diak_hermes_bridge.py`, 1797 lines) for the appendix.
Grepped the current main HEAD Swift tree to enumerate every call site
that talks to the bridge. Wrote `Docs/Phases/Phase1/BRIDGE_REALITY.md`
with the six sections SCOPE.md required plus the Appendix Nick asked
for.

## Commits Added

To be filled by the commit step. At checkpoint-write time, the branch
contains:

```
560693a Fix remaining placeholder timestamp in PROJECT_STATE.md   (main)
<this checkpoint, SHA filled after commit>                          (HEAD)
```

The work product (`BRIDGE_REALITY.md`) and this checkpoint will be
committed together in a single docs-only commit before push.

## Files Changed

Created:

- `Docs/Phases/Phase1/BRIDGE_REALITY.md` (new, ~480 lines, ~22 KB).
- `Docs/Phases/Phase1/CHECKPOINTS/20260511T191708Z-work-unit-1-bridge-reality-doc-complete.md`
  (this file).

No other file was created, modified, or deleted. Specifically:

- The bridge source file at
  `archive/bridge-experiment:Scripts/diak_hermes_bridge.py` was **not
  modified**. Read via `git show <ref>:<path>` only.
- No Swift file was modified.
- No file under `Scripts/` was modified.
- No file outside `Docs/Phases/Phase1/` was created.

## Build Result

N/A. Work Unit 1 is documentation only. No build was run.

## Test Result

N/A. Work Unit 1 is documentation only. No tests were run.

## Acceptance Criteria — Per-Criterion Result

SCOPE.md Work Unit 1 acceptance is one sentence: "doc exists, every
bridge endpoint is captured with a reference to the source line that
implements it, every Diak Swift call site that hits the bridge is
enumerated."

Decomposed:

1. **Doc exists** — PASS. `Docs/Phases/Phase1/BRIDGE_REALITY.md` is
   present with all six required sections (Overview, Process Model,
   Endpoints Served, External Dependencies, Internal State, Surface Diak
   Currently Depends On) plus the requested Appendix (Unauthorized WIP
   Delta).

2. **Every bridge endpoint is captured with a source-line citation** —
   PASS. 22 endpoint families across GET/POST/PATCH/DELETE are tabulated
   in the Endpoints Served section. Each row carries a `bridge.py:NNN`
   citation pointing at the line that registers the route in the
   relevant `do_*` handler, plus a citation for the implementing helper
   method when applicable. The full file was read end-to-end (lines
   1–1475).

3. **Every Diak Swift call site that hits the bridge is enumerated** —
   PASS. The "Surface Diak Currently Depends On" section lists the two
   non-test Swift source files that reference the bridge surface
   (`HermesAPIEndpointConfig.swift`, `URLSessionHermesAPIClient.swift`),
   the two construction sites for the live client
   (`HermesDesktopApp.swift:24`, `AppShellView.swift:17`), and the
   `streamEvents` stub (`URLSessionHermesAPIClient.swift:64–68`). It
   also tabulates every endpoint constant from
   `URLSessionHermesAPIClient.Endpoints` against the canonical bridge
   route table, flagging the one orphan reference
   (`/skills/draft-from-session/{id}` — Swift declares it; neither
   bridge version implements it). Four test files with bridge-URL
   fixtures are noted (M3/M4/M5/M6 tests at lines 130/139/159/271).

## Decisions Made During This Run

1. **Used `archive/bridge-experiment` HEAD as the canonical bridge
   source after Nick's ratification.** SCOPE.md said "the existing
   Python bridge at `Scripts/diak_hermes_bridge.py`" but that path
   doesn't exist on the current main tree (removed by Phase 0's
   architectural reset). I surfaced the missing-file situation before
   reading, presented four options (archive HEAD; d7acf33 WIP; both;
   stop), and Nick ratified the path:
   `archive/bridge-experiment` HEAD as primary, d7acf33 as appendix,
   skip the xcarchive build artifact, no branch checkouts.

2. **Did not check out `archive/bridge-experiment`.** Both bridge
   versions were read via `git show <ref>:<path>` and piped to
   `/tmp/bridge_canonical.py` and `/tmp/bridge_d7acf33.py` for
   convenience. Source-line citations refer to those refs, not to any
   working-tree file. CLAUDE.md Prohibition #4 ("Never modify branches
   matching `archive/*`") is respected — only reads.

3. **Did not save the bridge files to `Docs/Phases/Phase1/evidence/`.**
   Both copies are reproducible via `git show`, and the doc cites line
   numbers that can be verified inline. Duplicating 75 KB + 93 KB into
   the repo would be redundant.

4. **Cited the orphan Swift reference explicitly.**
   `URLSessionHermesAPIClient.swift:355` defines
   `/skills/draft-from-session/{id}`, but neither bridge version
   implements that path. Documented as an orphan rather than silently
   ignored.

5. **Distinguished "endpoints Swift calls" from "endpoints the bridge
   exposes."** The bridge has 22 endpoint families. Swift's
   URLSessionHermesAPIClient references 28 paths (one orphan). The
   bridge also exposes 4 endpoints with no Swift caller:
   `/sessions/{id}/stream` (SSE replay, Swift stubs it),
   `/sessions/{id}/canvas/artifacts`, `/settings/secrets`, and
   `/connectors/{id}/actions/send`. Recorded for Path B's planning.

## Questions for Nick

Six substantive Phase 1 scope concerns were surfaced during the
investigation. None can be resolved unilaterally per Prohibition #11.
Listed roughly in order of how load-bearing they are for Phase 1's
remaining work units.

**Q1. Who launches the bridge process today?** No Swift code spawns
`diak_hermes_bridge.py`. `grep -rn 'diak_hermes_bridge\|bridge_state
\|bridge\.py\|launchBridge\|startBridge\|Process(.*bridge'
--include='*.swift' HermesDesktop/` returns zero results on current
main. Phase 0.5 observed the bridge running at PID 64039 from
`Diak.app/Contents/Resources/diak_hermes_bridge.py`, but the current
build's `Resources/` is empty and no Swift code shells out the
launch. So the bridge was started outside Diak — by an earlier
`HermesBridgeManager.swift` (present on `archive/bridge-experiment`
per `git ls-tree`, removed by Phase 0 reset) or by you manually.

   **Phase 1 scope implication:** SCOPE.md Work Unit 6 says "Remove all
   calls to `Scripts/diak_hermes_bridge.py` from Swift code." If there
   are no such calls now, Work Unit 6's bridge-decommission step is
   already effectively done at the Swift level. The remaining question
   is whether something *outside* Swift (e.g. a manual launch in your
   shell, a launchd entry, a build-phase script) needs to stop too.

**Q2. The `/skills/draft-from-session/{id}` endpoint is referenced by
Swift but does not exist on either bridge version.**
`URLSessionHermesAPIClient.swift:355` declares it as
`Endpoints.skillDraftFromSession`. Any call to the corresponding client
method would 404. This is **dead Swift code referencing an endpoint
that was never implemented**. Path B's Phase 4 plan is Diak-native skill
drafting, so this orphan path can simply be deleted in Work Unit 6
along with other bridge cleanup. Flagging so the WU6 PR makes the
deletion explicit rather than a silent change.

**Q3. `streamEvents(sessionID:)` already throws `.notReachable`.**
`URLSessionHermesAPIClient.swift:64–68` is a permanent stub. So Diak
today never consumes the bridge's `/sessions/{id}/stream` SSE replay.
Phase 1 SCOPE.md Work Unit 4 plans real SSE via the API Server at
`/v1/runs/{run_id}/events`. That replaces the stub; no migration of
existing streaming behavior is needed because there is none. Flagging
because the SCOPE.md text reads as if streaming is being added to
something that already streams; it isn't.

**Q4. The bridge persists state that Phase 1 Work Unit 5 does not
migrate.** Work Unit 5 (Diak Session Store) plans SwiftData models for
`DiakSession`, `DiakMessage`, `DiakRun`. The bridge's
`bridge_state.json` (at `~/.hermes/diak/bridge_state.json`) currently
also holds **approvals, memory items, connector overlays, automation
overlays, skill enable-state, skill drafts, canvas artifacts, and
events**. Per Path B / Decision #13, Diak owns approvals, memory, and
the automation builder — those are Phase 3 and Phase 5 features, not
Phase 1. But the bridge_state file is *currently the only persistent
home* for that data on this Mac.

   **Phase 1 scope implication:** Does Work Unit 5 want to (a) define
   SwiftData schemas for sessions/messages/runs only (matches SCOPE.md
   as written, no migration), or (b) read `bridge_state.json` once on
   first launch to migrate existing approvals/memory/automations into
   the new SwiftData store? Option (a) means losing whatever
   approvals/memory/automation history exists in
   `bridge_state.json` when the bridge is decommissioned in Work Unit 6.
   Option (b) is a Phase 1 scope expansion. Neither is intrinsically
   wrong; you decide.

**Q5. The d7acf33 WIP has a real Composio integration the canonical
archive does not.** d7acf33 adds ~366 lines including
`_fetch_composio_toolkits`, `_create_composio_setup_url`,
`_normalize_composio_list_payload`, and the new `/settings/secrets/{id}`
CRUD endpoints — all making real HTTPS calls to
`backend.composio.dev/api/v1` via `urllib.request`. The canonical
archive only stubs Composio. Path B's Phase 4 plan says Diak does
Composio natively in Swift. Two reasonable readings:

   (a) The d7acf33 code is the WIP that Phase 4 will reimplement in
   Swift. Phase 1 does nothing with it; Phase 4 mines it as a contract
   reference.

   (b) Phase 4 inherits the Python HTTP-call shapes verbatim and writes
   the Swift translation against them.

   No action needed in Phase 1 either way. Flagging for the Phase 4
   conversation later.

**Q6. Bridge surface area Diak has never consumed.** The bridge
implements four endpoints that current Diak doesn't call:
`/sessions/{id}/canvas/artifacts`, `/sessions/{id}/stream`,
`/settings/secrets`, `/connectors/{id}/actions/send`. These are dead
surface from Diak's perspective. The Path B replacement does not need
to reimplement them. Flagging only because SCOPE.md Work Unit 3
("Dashboard HTTP Client") might otherwise inherit them by accident if I
treat "the surface Diak depends on today" as "everything the bridge
exposes." It isn't. The Surface section of BRIDGE_REALITY.md makes
this explicit, but worth confirming the Work Unit 3 work avoids
expanding to bridge surface Diak doesn't actually need.

## Recommendation for Next Work Unit

**Work Unit 2: Hermes Process Supervisor.** Ready to start in principle.
SCOPE.md Work Unit 2 is well-scoped, references concrete file paths,
and depends only on the Phase 0.5 Reality Doc (already ratified) plus
the dashboard binary at `~/.hermes/.../hermes`. Nothing in BRIDGE_REALITY
blocks it.

That said, **two of the surfaced questions usefully precede Work Unit
2's ratification:**

- **Q1 (who launches the bridge today?)** — Useful to know before WU2,
  because if there's a launchd entry or shell-script launcher that
  currently starts the bridge, the same mechanism may need adjustment
  when `HermesProcessSupervisor` becomes the source of truth for
  process management. Easy answer: probably nothing automated. Worth
  confirming.
- **Q4 (Work Unit 5 migration scope)** — Not blocking WU2 itself, but
  the answer shapes WU5's surface area. Useful to settle before WU5
  is started.

Q2, Q3, Q5, Q6 are not blockers for any specific upcoming work unit.
They're cleanup line items / future-phase notes. Recording them so
they're not lost.

**Concrete recommendation:** ratify Work Unit 1, answer Q1 (and
ideally Q4) at your discretion, then green-light Work Unit 2 to begin
on this same branch. No additional doc work is needed before WU2.

## Out-of-Scope Items Observed

1. **`Scripts/` directory contains only build/release shell scripts**
   on current main, no Python. The bridge file was removed by Phase 0's
   architectural reset. Worth confirming
   `archive/bridge-experiment:Scripts/diak_hermes_bridge.py` is the
   most-recent intentionally-archived version per Decision #13; the
   `d7acf33` commit is newer in time but explicitly described as
   "unauthorized" in its own commit message.

2. **`HermesBridgeManager.swift` exists on `archive/bridge-experiment`**
   (per `git ls-tree -r archive/bridge-experiment | grep -i bridge`)
   but not on `main`. Phase 0 stripped it out. This was almost
   certainly the Swift side of Diak's bridge management before the
   reset. If you want a reference for what the *full* bridge launch
   path used to look like (for comparison to the upcoming
   `HermesProcessSupervisor`), it lives there. Not Phase 1 scope to
   resurrect; just noting it exists.

3. **The `xcarchive` build artifact at
   `build/Diak.xcarchive/.../diak_hermes_bridge.py` is 34 163 bytes** —
   substantially smaller than both git-tracked versions (canonical
   75 367, WIP 93 361). Neither bytewise nor textually inspected per
   Nick's direction. Likely a much earlier shipped snapshot. Not
   touched.

4. **Pre-existing Phase 0.5 known issues remain.** Three stale
   `Diak.app` bundles register `diak://` with LaunchServices; `zsh`
   builtin `log` still shadows `/usr/bin/log`; Hermes is 426 commits
   behind upstream. None relevant to Work Unit 1.

5. **No tests were affected** in this work unit. The 4 test files that
   reference `127.0.0.1:8765` (M3/M4/M5/M6 client tests) use the bridge
   port as a fixture URL for response mocking — they don't actually
   start the bridge. They should continue to pass through Work Units
   2–5 since the URL is just a string. They will need updating in
   Work Unit 6 when the bridge is decommissioned and the client's base
   URL changes.
