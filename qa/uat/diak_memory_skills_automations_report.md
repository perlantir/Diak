# Diak Memories / Skills / Automations UAT Report

## Summary
- Target: Diak macOS app + app-owned Hermes bridge (`127.0.0.1:8765`)
- Scope: Memories create/edit/read/delete, Skills direct draft/create/enable persistence, Automations create/schedule/delivery/test-run/delete cron pairing.
- Overall result: PASS for API/state contract and app launch/bridge ownership; PARTIAL for actual SwiftUI click-through of each CRUD form because macOS accessibility automation could not reliably address every sidebar/form control in this desktop session.

## Evidence
- UAT harness: `qa/uat/memory_skills_automations_uat.py`
- PASS state evidence JSON: `qa/uat/diak_memory_skills_automations_uat_1778458917.json`
- Sanitized live app-owned bridge probe: `qa/uat/live/diak_live_bridge_probe_20260510_192034.log`
- App launch screenshots were produced locally during the run but were intentionally not committed to avoid adding large/private desktop captures to git.

## Checklist Results

### 1. Memory create/edit/read/delete persists
Status: PASS
Expected: Bridge accepts acknowledged memory create/update, persists readback, deletes record, deleted record returns 404.
Actual: PASS in UAT JSON; created `mem-bca38ec3863f4857`, readback body `Updated UAT memory body persisted.`, delete returned true, follow-up GET returned 404.
Evidence: `qa/uat/diak_memory_skills_automations_uat_1778458917.json`

### 2. Skill direct draft create/enable persists
Status: PASS
Expected: Direct skill draft creates a skill, enable toggle persists, `/skills` catalog reflects enabled active skill.
Actual: PASS; created `skill-direct-uat-qa-skill`, enable PATCH returned active, catalog showed `is_enabled: true`.
Evidence: `qa/uat/diak_memory_skills_automations_uat_1778458917.json`

### 3. Automation create/schedule/delivery/test-run/delete cron pair
Status: PASS
Expected: Create passes schedule and delivery target to Hermes cron, update changes delivery/schedule, test-run records success, delete removes paired cron job.
Actual: PASS; create command included `hermes cron create 30m ... --deliver telegram --repeat 1`, update set delivery to local/disabled, test-run succeeded with DONE, delete invoked `hermes cron remove cafebabe12345678`.
Evidence: `qa/uat/diak_memory_skills_automations_uat_1778458917.json`

### 4. Actual app-owned bridge route availability
Status: PASS
Expected: Relaunched Diak owns bridge listener and exposes `/version`, `/memory`, `/skills`, `/automations`.
Actual: PASS; listener is Python bridge inside current DerivedData `Diak.app/Contents/Resources/diak_hermes_bridge.py`, contract `m12-slice6`, routes present.
Evidence: `qa/uat/live/diak_live_bridge_probe_20260510_192034.log`

### 5. Actual SwiftUI form click-through
Status: PARTIAL
Expected: Human-visible navigation and CRUD forms clicked in app.
Actual: App launched and onboarding was skipped in the local desktop session. Full Memory/Skills/Automations form click-through was not completed due to desktop accessibility targeting limits; covered instead by Swift view-model tests, URLSession route tests, bridge tests, and UAT API/state proof.
Evidence: full Swift/Python regression gates plus sanitized route probe; raw screenshots were not committed to avoid private desktop capture leakage.

## Known Remaining Release Gap
- External distribution remains BLOCKED until Developer ID signing, notarization, stapling, and Gatekeeper assessment are completed. Current Debug app is ad-hoc signed and `spctl` rejects it, as expected for local debug builds.
