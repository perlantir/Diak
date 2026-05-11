# Phase 0.5 — Hermes Reality Doc — Scope

## Goal

Document what real Hermes actually exposes on this Mac. No assumptions. No
guesses. Direct observation, recorded as a markdown document at
`Docs/Phases/Phase1/REALITY.md`.

This document is a hard gate before any Phase 1 code can be written. The
Phase 1 plan locked the assumption that Hermes can be launched as an HTTP or
socket server with specific endpoints. The earlier Phase 1 attempt failed
because that assumption was wrong (the `daemon` subcommand doesn't exist).
This phase exists to replace assumption with observation.

## Branch

`phase/0.5-reality-doc` (create from current main at SHA `5cf4060`)

## In-Scope Activities

Investigation and documentation only. Specifically:

- Run `hermes --help` and document the full output verbatim.
- Run `--help` for every subcommand that could plausibly start an HTTP or
  socket server. Confirmed subcommands from prior investigation include:
  `chat`, `gateway`, `setup`, `status`, `cron`, `webhook`. Document each.
- Run `hermes --version` and document the exact version installed.
- Start Hermes as an HTTP/socket server using whatever the real subcommand
  is (almost certainly `hermes gateway start` or similar — confirm by
  reading the gateway subcommand's `--help`). Document the exact command,
  any required flags, and any environment variables consumed.
- Identify the port (TCP) or socket path (UDS) the server binds to.
- Identify the authentication mechanism: none, bearer token, API key,
  file-based secret, or other. Document where Hermes reads its auth from
  (env var, file path, command-line flag, etc.).
- Test endpoints using `curl`. Try at minimum:
  - `/health`
  - `/version`
  - `/sessions`
  - `/sessions/{some-id}/messages` (if sessions exist; create one if needed)
  - `/skills`
  - `/approvals`
  - `/connectors`
  - `/automations`
  - `/memory`
  - `/config`
  - Any other endpoints the gateway subcommand's help output mentions
- For each endpoint that exists, document:
  - HTTP method
  - Full path
  - Whether authentication is required
  - Request body shape (if POST/PATCH)
  - Response body shape with an example
  - Example `curl` invocation that succeeded
- Test streaming support: attempt `curl -N` against the most likely
  streaming endpoints. Document whether Hermes speaks SSE, WebSocket,
  chunked HTTP, or only plain request-response.
- Document where Hermes stores its state on disk (config directory,
  sessions directory, skills directory, any database files).
- Document any quirks discovered during investigation, including but not
  limited to: known restart behavior, hang conditions, error message
  formats, environment variable expectations.

## Out-of-Scope

- Writing any Swift code.
- Modifying any Diak source file (including tests).
- Touching anything under `Scripts/`, including the Python bridge.
- Making the Path A vs Path B decision (Python bridge as adapter vs direct
  integration). That decision is Nick's after reviewing the Reality Doc.
- Modifying any file outside `Docs/Phases/Phase1/`.
- Starting any Phase 1 implementation work.
- Cleaning up the three stale `Diak.app` bundles noted in
  `Docs/PROJECT_STATE.md` known issues.

## Deliverable

A single file at `Docs/Phases/Phase1/REALITY.md` with sections in this exact
order:

    # Hermes Runtime Reality

    ## Version

    ## CLI Subcommands

    ## How to Start the HTTP/Socket Server

    ## Transport

    ## Authentication

    ## Endpoints
    (one subsection per endpoint, in this order: method, path, auth required,
    request shape, response shape, example curl, example response)

    ## Streaming

    ## State Directory

    ## Quirks and Known Issues

    ## Compatibility Notes

Every claim must be backed by direct observation. If a section can't be
filled in because the relevant behavior doesn't exist, write "Not supported"
or "Not observed" with a brief note explaining what was tested.

If commands or curl invocations produce long output, capture the most
important parts inline and optionally link to evidence files saved under
`Docs/Phases/Phase1/evidence/`. Evidence files are allowed under
`Docs/Phases/Phase1/` per scope.

## Acceptance Criteria

1. `Docs/Phases/Phase1/REALITY.md` exists and follows the section structure
   above.
2. Every section is filled in based on direct observation.
3. Every endpoint claim is backed by an actual `curl` invocation captured
   in the document or in an evidence file.
4. The document contains no speculation about what Hermes "should" do —
   only what it does on this machine right now.
5. No Swift files have been modified.
6. No files outside `Docs/Phases/Phase1/` have been created or modified.
7. The branch `phase/0.5-reality-doc` is pushed to origin.
8. A final checkpoint at
   `Docs/Phases/Phase1/CHECKPOINTS/<UTC-timestamp>-reality-doc-complete.md`
   summarizes findings per the checkpoint format in CLAUDE.md.
9. The checkpoint's "Recommendation for Next Work Unit" section includes
   the agent's read on whether the Phase 1 plan's locked assumptions
   (UDS endpoint, bearer auth, specific endpoint paths) match the observed
   reality, or whether they need to be revised.

## What to Do When Acceptance Passes

Stop. Push the branch and the checkpoint to origin. Do not begin any Phase
1 implementation. Nick reviews the Reality Doc and decides Path A
(keep Python bridge as adapter) vs Path B (direct integration with real
Hermes). After that decision is made, Nick will update PROJECT_STATE.md and
write the Phase 1 SCOPE.md.

## What to Do If Investigation Surfaces Surprises

If you discover something that contradicts the locked architectural
decisions in PROJECT_STATE.md (for example: Hermes doesn't support socket
auth at all, or there is no `gateway` subcommand, or the endpoints have
totally different paths) — do not try to resolve the contradiction.
Document the contradiction clearly in REALITY.md and flag it explicitly in
the checkpoint's "Questions for Nick" section. The locked decisions are
Nick's to change, not yours.
