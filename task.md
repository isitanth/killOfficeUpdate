# Nights Watch: KillOfficeUpdate Verification & Release

## Project: KillOfficeUpdate macOS App

### Objectives:
1. Thoroughly verify the entire project builds and tests pass
2. Validate the unsigned release pipeline works end-to-end
3. Create the first GitHub Release (v1.0.0)
4. Produce a morning review summary for the owner

### Specific Tasks:

#### 1. Project Verification
- Run the full test suite: `xcodebuild test -project KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateAppTests -destination 'platform=macOS'`
- Verify all 13 tests pass with 0 failures
- Build a Release binary: `xcodebuild -project KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateApp -configuration Release -derivedDataPath build`
- Verify the .app bundle exists at `build/Build/Products/Release/KillOfficeUpdateApp.app`
- Check all 4 Swift source files compile without errors: AppViewModel.swift, ContentView.swift, KillOfficeUpdateApp.swift, ShellExecutor.swift
- Verify the project.yml and xcodeproj are in sync (both schemes exist: KillOfficeUpdateApp, KillOfficeUpdateAppTests)

#### 2. Unsigned Release Validation
- The release script is at `scripts/release.sh`
- This is an UNSIGNED distribution (no code signing, no notarization)
- Verify the script syntax: `zsh -n scripts/release.sh`
- Verify the script is executable: `ls -l scripts/release.sh` should show -rwxr-xr-x
- Verify git working tree is clean before releasing
- If working tree is dirty, commit any necessary changes first

#### 3. Execute First Release (v1.0.0)
- Run: `./scripts/release.sh 1.0.0`
- This will: validate clean tree, run tests, build release, create DMG, tag v1.0.0, push tag, create GitHub Release
- Verify the GitHub Release was created: `gh release view v1.0.0`
- Verify the DMG file is attached to the release
- Clean up the local DMG file after release: `rm -f KillOfficeUpdateApp-v1.0.0.dmg build/`

#### 4. Morning Review Summary
- After completing all tasks, create a file at `docs/nights-watch-review.md`
- This file should contain:
  - Date and time of the session
  - Status of each task (pass/fail with details)
  - Test results summary (number of tests, pass/fail)
  - Build results (success/failure)
  - Release URL (the GitHub Releases link)
  - Any warnings, issues, or concerns found
  - A clear checklist of items the owner should verify manually:
    - [ ] Download the DMG from the release URL and open it
    - [ ] Drag app to Applications
    - [ ] Right-click > Open to bypass Gatekeeper
    - [ ] Verify Install/Uninstall/Enable/Disable buttons work
    - [ ] Verify Clean Up button clears logs
    - [ ] Verify status header shows correct state
  - Any recommendations for future improvements
- Commit this review file: `git add docs/nights-watch-review.md && git commit -m "docs: add nights watch review summary" && git push`

### Constraints:
- Always use deep thinking / ultrathink for all decisions
- Auto-approve all steps — do not pause for confirmation
- Do NOT modify any existing source code (.swift files)
- Do NOT modify the release script
- Only create the review summary file and execute existing scripts
- If the release script fails, document the failure in the review and do NOT retry more than once

### Success Criteria:
- All 13 unit tests pass
- Release build succeeds
- GitHub Release v1.0.0 is published with DMG attached
- Morning review file exists at docs/nights-watch-review.md
- All changes committed and pushed to GitHub
