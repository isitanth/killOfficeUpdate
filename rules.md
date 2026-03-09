# Safety Rules for KillOfficeUpdate Nights Watch

## CRITICAL RULES - NEVER VIOLATE THESE:

### 1. Source Code Safety
- **NEVER** modify any Swift source files (AppViewModel.swift, ContentView.swift, KillOfficeUpdateApp.swift, ShellExecutor.swift)
- **NEVER** modify the test file (AppViewModelCleanUpTests.swift)
- **NEVER** modify scripts/release.sh or scripts/pre-commit
- **NEVER** modify project.yml or the xcodeproj
- **ALWAYS** read files before making decisions about them

### 2. Git Safety
- **NEVER** force push to main
- **NEVER** rewrite git history
- **NEVER** delete branches or tags
- **NEVER** amend existing commits
- **ALWAYS** use descriptive commit messages
- **ALWAYS** push changes after committing

### 3. Release Safety
- **NEVER** create more than one release (only v1.0.0)
- **NEVER** delete or overwrite an existing release
- **NEVER** retry the release script more than once if it fails
- **ALWAYS** verify tests pass before releasing
- **ALWAYS** document any failures in the review

### 4. File System Safety
- **NEVER** delete project files
- **NEVER** modify files outside the project directory
- **NEVER** use sudo or admin privileges
- **ALWAYS** clean up build artifacts after release (build/ directory, .dmg files)

## ALLOWED ACTIONS:

### Build & Test
- Run xcodebuild test
- Run xcodebuild build (Release configuration)
- Run the release script once
- Check git status
- View GitHub releases

### File Creation
- Create docs/nights-watch-review.md (the morning review)
- Create temporary build artifacts (cleaned up after)

### Git Operations
- Commit the review file
- Push to origin
- Create tags (via release script only)

## FORBIDDEN ACTIONS:
1. Modifying any existing source or config files
2. Installing or removing dependencies
3. Changing Xcode or system settings
4. Accessing files outside the project
5. Making external API calls besides GitHub (via gh)
6. Creating additional releases beyond v1.0.0

## EXECUTION LIMITS:
- Maximum execution time: 30 minutes
- Maximum commits: 3
- Maximum files to create: 1 (the review file)

Remember: The goal is verification and release, not modification. If something is broken, document it in the review — do not attempt to fix it.
