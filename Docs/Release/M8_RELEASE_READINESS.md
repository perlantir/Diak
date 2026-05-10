# M8 Release Readiness — Diak

Updated: 2026-05-10

## Current release target

- Product name: **Diak**
- Underlying runtime name: **Hermes Agent** / **Hermes Engine**
- Version: `0.1.0` private/local release checkpoint
- Bundle display name: `Diak`
- Bundle identifier: `com.uberkiwi.diak`
- GitHub backup: `https://github.com/perlantir/Diak`

M8 is not an App Store release. It is the first packaging/release-readiness checkpoint for a Mac-native private/public-beta distribution path.

## Signing and notarization plan

### Required inputs outside git

Do **not** commit these values or generated secrets:

- Apple Developer Program membership.
- Developer ID Application certificate installed in the local login keychain.
- Apple team ID.
- App Store Connect API key or notarytool keychain profile.
- Sparkle EdDSA signing private key, when updater support is added.

### Recommended signing path

1. Keep Debug/local builds unsigned or ad-hoc as needed for local QA.
2. For private signed distribution, use Developer ID Application signing with hardened runtime enabled.
3. Archive with Xcode using `Scripts/build_release.sh`.
4. Export using a local `ExportOptions.plist` that is not committed to the repo.
5. Notarize the exported `.app` or `.dmg` with `xcrun notarytool` using a stored keychain profile.
6. Staple the notarization ticket to the `.app` and final `.dmg`.
7. Validate with Gatekeeper using `spctl` before publishing.

### Local commands once credentials exist

```bash
# Store credentials once, outside repo. Replace values locally only.
xcrun notarytool store-credentials diak-notary-profile \
  --apple-id "[REDACTED]" \
  --team-id "[REDACTED]" \
  --password "[REDACTED]"

# Build/archive/export. ExportOptions.plist remains local/untracked.
EXPORT_OPTIONS_PLIST=~/secure/diak/ExportOptions.plist Scripts/build_release.sh

# Create DMG from exported or archived app.
Scripts/create_dmg.sh build/export/Diak.app

# Notarize and staple.
xcrun notarytool submit build/dist/Diak-0.1.0.dmg \
  --keychain-profile diak-notary-profile \
  --wait
xcrun stapler staple build/dist/Diak-0.1.0.dmg
spctl --assess --type open --context context:primary-signature -vv build/dist/Diak-0.1.0.dmg
```

## Build/export scripts

### Release/archive

```bash
Scripts/build_release.sh
```

Default behavior:

- Runs `xcodegen generate`.
- Builds the `HermesDesktop` scheme in Release configuration.
- Archives to `build/Diak.xcarchive`.
- Skips export unless `EXPORT_OPTIONS_PLIST` is provided.

### DMG

```bash
Scripts/create_dmg.sh build/Diak.xcarchive/Products/Applications/Diak.app
```

Default behavior:

- Creates `build/dist/Diak-0.1.0.dmg`.
- Includes a `/Applications` symlink.
- Writes `build/dist/Diak-0.1.0.dmg.sha256`.

## Release checklist

### Preflight

- [ ] `git status --short` is clean before release branch/tag.
- [ ] `xcodegen generate` succeeds.
- [ ] `xcodebuild -list` shows scheme `HermesDesktop`.
- [ ] Debug build succeeds.
- [ ] Full test suite succeeds.
- [ ] `git diff --check` succeeds.
- [ ] `CFBundleDisplayName` is `Diak`.
- [ ] Built app bundle is `Diak.app`.
- [ ] Product-facing UI says `Diak`; engine-facing UI may say `Hermes Agent` / `Hermes Engine`.

### Package

- [ ] Release archive succeeds.
- [ ] Export succeeds with local signing options, if signing credentials are configured.
- [ ] DMG creation succeeds.
- [ ] SHA-256 checksum is generated.
- [ ] Notarization succeeds, if signing credentials are configured.
- [ ] Stapling succeeds for `.app` and `.dmg`, if notarized.
- [ ] Gatekeeper assessment passes on a clean Mac account or VM.

### Smoke install

- [ ] Drag Diak.app from DMG to `/Applications`.
- [ ] First launch opens Diak and does not show unexpected Hermes Desktop branding.
- [ ] Onboarding can be completed or skipped.
- [ ] Offline Hermes Agent daemon state is shown truthfully.
- [ ] Main window opens at normal and compact widths.
- [ ] Menu bar extra opens.
- [ ] Quick Prompt window opens with `⇧⌘K`.
- [ ] No real connector sends/posts occur during smoke testing.

## Rollback plan

- Keep the previous signed DMG and checksum available until the new build passes smoke install.
- If notarization or Gatekeeper fails, do not publish; rebuild with corrected signing/export options.
- If UI QA finds blocker issues, publish no artifact and continue from the M8 branch/commit.
- If a release is already published, remove or mark the DMG as superseded and publish a replacement with a bumped build number.
