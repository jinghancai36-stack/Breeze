# Milestone 9 — Source Release Readiness

Milestone 9 prepares Breeze for an honest source-only GitHub release. It does not publish a repository, upload an artifact, or claim that an unnotarized development build is suitable for general fan control.

## Repository readiness

- [x] Changelog and v0.8.0 source-release notes.
- [x] Security reporting policy for Helper and hardware-control issues.
- [x] Safety-first installation, recovery, and removal guide.
- [x] Structured bug and hardware-compatibility issue templates.
- [x] Pull-request safety and privacy checklist.
- [x] Generated artifacts and credential-shaped files remain ignored.

## Reproducibility

- [x] Repository audit covers tracked output, credential file types, large files, common secret patterns, and author-email privacy notice.
- [x] One-command Release gate covers Debug/Release tests, plist validation, static analysis, isolated Release build, version matching, arm64 architecture, and strict deep signing verification.
- [x] Source archive script uses `git archive` from a clean commit and emits a SHA-256 checksum.
- [x] Clean-worktree Release gate executed on the Phase 9 commit.
- [x] v0.8.0 source archive generated and its checksum verified.

## Publication boundary

- [x] Existing commit author and committer emails are rewritten to the repository owner's GitHub noreply address before publication.
- [x] Repository links target `jinghancai36-stack/Breeze`.
- [x] GitHub remote creation and first `main` push were explicitly confirmed by the repository owner.
- [ ] Hosted CI is selected only after confirming a runner with the required macOS/Xcode toolchain.
- [ ] Public binary distribution remains deferred until Developer ID signing, notarization, and clean-Mac installation testing are available.
