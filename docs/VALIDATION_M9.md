# Milestone 9 Validation

Validation target: `MacBookPro18,3`, Apple M1 Pro, macOS 26 development environment.

## Repository audit — 2026-08-13

- 60 tracked files and 6 pre-Phase-9 commits were inspected before new release files were added.
- No build products, credential file types, tracked files larger than 1 MiB, or common secret patterns were found in the current tree or Git history.
- No Git remote is configured, so no source or artifact was published.
- The repository owner supplied a GitHub noreply address; all six existing commits were rewritten before publication, and the local repository identity now uses that address.

## Local Release gate

The eight-step gate passed from the Phase 9 working tree with `BREEZE_ALLOW_DIRTY=1`:

- repository audit and `git diff --check`;
- both property lists validated with `plutil`;
- Debug: 9 hardware tests and 63 App/Helper tests;
- optimized Release: 9 hardware tests and 63 App/Helper tests;
- Xcode Release static analysis;
- isolated arm64 Release build for Breeze 0.8.0 build 13;
- app/Helper version match;
- local Apple Development signing and strict deep verification.

The first gate run exposed a test-only asynchronous race in the sleep-safety assertion. The assertion now waits for the Automatic-restore completion state instead of only the stub request count. The focused test passed five consecutive runs before the complete Debug and Release suites passed.

## Remaining publication gates

- Run the Release gate again from the clean Phase 9 commit without `BREEZE_ALLOW_DIRTY`.
- Generate the source archive from that clean commit and verify its SHA-256 checksum.
- Confirm the GitHub repository has been created as an empty repository at `jinghancai36-stack/Breeze`.
- Obtain explicit approval before configuring a remote, pushing commits, or creating a GitHub release.

No installed Breeze executable or privileged Helper was modified during this validation.
