# Diak Updater Strategy

Updated: 2026-05-10

## Decision

Use **Sparkle 2** for Diak's public/private macOS updater once the app moves beyond local QA builds.

Reasons:

- Native macOS update UX.
- Developer ID distribution support.
- EdDSA update signing independent of Apple notarization.
- Appcast-based hosting works with simple static hosting.
- Mature rollback/phased-release patterns.

## M8 scope

M8 documents the updater strategy but does not integrate Sparkle yet. First private builds can ship through a manual DMG download path while release packaging, signing, notarization, and QA stabilize.

## Phase 0: Manual update fallback

Use this until Sparkle is integrated:

1. Publish `Diak-<version>.dmg` and `.sha256` to a controlled download location.
2. Include release notes and minimum macOS version.
3. Users download, verify if needed, and drag `Diak.app` to `/Applications`.
4. Diak displays its version in About/Settings once that surface is added.

Manual fallback is acceptable for private testing but not ideal for public release because users may miss critical fixes.

## Phase 1: Sparkle 2 integration

Future implementation tasks:

1. Add Sparkle 2 dependency to the Xcode project.
2. Add `SUUpdater` or `SPUStandardUpdaterController` app integration.
3. Add an appcast URL in Info.plist or runtime config.
4. Generate Sparkle EdDSA keys and store the private key outside git.
5. Add the public key to app configuration.
6. Update release script to sign Sparkle update archives.
7. Generate appcast XML during release.
8. Host appcast and DMG on stable HTTPS hosting.
9. Add QA tests for update available, no update, failed download, and skipped version states.

## Required secrets and storage rules

Never commit:

- Sparkle private EdDSA key.
- Apple Developer credentials.
- Notary credentials.
- Private appcast credentials or deploy tokens.

Safe to commit:

- Sparkle public key.
- Appcast public URL.
- Release scripts that read secrets from environment/keychain.
- Documentation with `[REDACTED]` placeholders.

## Appcast hosting options

Preferred options, in order:

1. Static HTTPS hosting on Cloudflare Pages/R2.
2. GitHub Releases plus a small static appcast file.
3. S3-compatible bucket with CDN.

The appcast URL must be stable before public release because moving update URLs after distribution creates support friction.

## QA gates before enabling auto-update

- Sparkle framework is correctly signed inside `Diak.app`.
- The app remains notarized after Sparkle integration.
- A clean install sees the current version as up to date.
- An older build sees the new version and downloads it.
- Sparkle signature verification fails closed for tampered update archives.
- User can skip/postpone an update.
- No update check blocks app launch or onboarding.
