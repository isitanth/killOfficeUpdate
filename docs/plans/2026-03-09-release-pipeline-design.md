# Release Pipeline Design

## Summary

A single `scripts/release.sh <version>` command that builds, signs, notarizes, creates a DMG, and publishes to GitHub Releases. Manual local execution — no CI/CD.

## Prerequisites (one-time setup)

1. **Developer ID Application certificate** — Xcode > Settings > Accounts > Manage Certificates
2. **App-specific password** — generated at appleid.apple.com
3. **Keychain profile** — store credentials once:
   ```
   xcrun notarytool store-credentials "KillOfficeUpdate" \
     --apple-id YOUR_EMAIL \
     --team-id YOUR_TEAM_ID \
     --password YOUR_APP_SPECIFIC_PASSWORD
   ```
4. **GitHub repo** — `gh repo create killOfficeUpdate --public --push`

## Release Script Flow

`./scripts/release.sh 1.0.0` performs these steps in order, aborting on any failure:

| Step | What it does |
|------|-------------|
| 1. Validate | Check version arg provided, git working tree is clean |
| 2. Test | Run `xcodebuild test` — abort if any test fails |
| 3. Build | `xcodebuild -configuration Release` signed with Developer ID Application |
| 4. Create DMG | `hdiutil create` with app bundle + Applications symlink |
| 5. Notarize | `xcrun notarytool submit` with keychain profile, waits for completion |
| 6. Staple | `xcrun stapler staple` embeds ticket in DMG |
| 7. Tag | `git tag v<version>` and push tags |
| 8. Release | `gh release create` with DMG attached, auto-generated notes |

## DMG Layout

- Contains: `KillOfficeUpdateApp.app` + symlink to `/Applications`
- Volume name: "KillOfficeUpdate"
- Output filename: `KillOfficeUpdateApp-v<version>.dmg`
- Simple layout — no custom background image

## Key Decisions

- **Single script, not Makefile** — one command reduces human error
- **Keychain for credentials** — no secrets in code or env vars
- **Tests gate the release** — build only proceeds if all tests pass
- **Git tag before GitHub Release** — tags mark the exact commit that was released
- **No CI/CD** — manual local execution, can automate with GitHub Actions later
